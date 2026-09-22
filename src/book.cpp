#include "book.h"

#include <QCryptographicHash>
#include <QFutureWatcher>
#include <QDir>
#include <QFileInfo>
#include <QPointer>
#include <QSettings>
#include <QVariantMap>
#include <QtConcurrent/QtConcurrentRun>

using namespace Qt::StringLiterals;

namespace {
// Per-book bookmark key. The path itself is a terrible settings key (slashes,
// unicode, length), so hash it and keep the readable part as a comment.
QString bookmarkKey(const QString &path)
{
    const QByteArray h = QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1);
    return u"bookmarks/"_s + QString::fromLatin1(h.toHex().left(16));
}

QString playlistKey(const QString &path)
{
    const QByteArray h = QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1);
    return u"playlist/"_s + QString::fromLatin1(h.toHex().left(16));
}

// Playback position of one episode. Deliberately a different prefix from
// bookmarks/: a page number and a timestamp are not the same thing, and mixing
// them would make old settings files mean something new.
QString resumeKey(const QString &url)
{
    const QByteArray h = QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Sha1);
    return u"resume/"_s + QString::fromLatin1(h.toHex().left(16));
}

constexpr int kMaxRecent = 24;

// Below this, whatever happened was not really watching, and above the tail end
// the episode is finished -- neither is worth reopening at.
constexpr double kResumeFloor = 30.0;
constexpr double kResumeTailFraction = 0.98;
} // namespace

// ------------------------------------------------------------- PageStore ----

void PageStore::set(std::shared_ptr<PageSource> source)
{
    QMutexLocker lock(&m_mutex);
    m_source = std::move(source);
    ++m_generation;
}

std::shared_ptr<PageSource> PageStore::get(int generation) const
{
    QMutexLocker lock(&m_mutex);
    if (generation != m_generation)
        return nullptr;
    return m_source;
}

int PageStore::generation() const
{
    QMutexLocker lock(&m_mutex);
    return m_generation;
}

// ------------------------------------------------------------------ Book ----

Book::Book(QObject *parent)
    : QObject(parent)
{
    loadSettings();
}

Book::~Book()
{
    rememberPosition();
}

void Book::loadSettings()
{
    QSettings s;
    m_recent = s.value(u"recent"_s).toStringList();
    m_rightToLeft = s.value(u"rightToLeft"_s, false).toBool();
    m_fitMode = s.value(u"fitMode"_s, int(FitWindow)).toInt();
}

QString Book::pageName() const
{
    if (m_media) {
        if (m_index < 0 || m_index >= m_media->count())
            return {};
        return m_media->entries().at(m_index).display;
    }
    auto src = m_store.get(m_generation);
    if (!src || m_index < 0 || m_index >= src->count())
        return {};
    return src->entries().at(m_index).display;
}

QString Book::pageFilePath(int i) const
{
    auto src = m_store.get(m_generation);
    if (!src || i < 0 || i >= src->count())
        return {};
    return src->filePath(i);
}

QString Book::shortName(const QString &path) const
{
    const QFileInfo fi(path);
    return fi.isDir() ? fi.fileName() : fi.completeBaseName();
}

void Book::openUrl(const QUrl &url)
{
    openPath(url.isLocalFile() ? url.toLocalFile() : url.toString());
}

void Book::openPath(const QString &path)
{
    if (path.isEmpty())
        return;

    rememberPosition();

    const QString absolute = QFileInfo(path).absoluteFilePath();
    const quint64 token = ++m_openToken;

    m_busy = true;
    emit busyChanged();

    // Indexing walks the whole archive, which is quick for a chapter and not so
    // quick for a 2 GB omnibus -- either way it does not belong on the UI thread.
    QPointer<Book> self(this);
    auto future = QtConcurrent::run([absolute] {
        Opened result;
#ifdef R9VIEW_VIDEO
        // Video is asked first, and answers only when it finds something it can
        // play, so a folder of pictures or a comic archive falls straight
        // through to the reader exactly as it always did.
        result.media = Playlist::open(absolute, &result.start, &result.error);
        if (result.media)
            return result;
        result.error.clear();
#endif
        result.pages = PageSource::open(absolute, &result.start, &result.error);
        return result;
    });

    auto *watcher = new QFutureWatcher<Opened>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [self, watcher, token] {
        const Opened result = watcher->result();
        watcher->deleteLater();
        if (!self || token != self->m_openToken)
            return; // a newer open won the race
        self->adopt(result);
    });
    watcher->setFuture(future);
}

void Book::adopt(const Opened &result)
{
    m_busy = false;
    emit busyChanged();

    if (!result.pages && !result.media) {
        m_error = result.error.isEmpty() ? u"could not open that"_s : result.error;
        emit errorChanged();
        return;
    }

    QString path;
    if (result.media) {
        path = result.media->location();
        m_title = result.media->title();
        m_isArchive = result.media->isArchive();
        m_count = result.media->count();
        m_media = result.media;
        // The image pipeline is emptied rather than left holding the last book:
        // its generation still bumps, so any page request already in flight
        // resolves to nothing instead of drawing over a video.
        m_store.set(nullptr);
        m_kind = Video;
    } else {
        path = result.pages->location();
        m_title = result.pages->title();
        m_isArchive = result.pages->isArchive();
        m_count = result.pages->count();
        m_media.reset();
        m_store.set(result.pages);
        m_kind = Images;
    }
    m_location = path;
    m_generation = m_store.generation();

    // Resume where this was left, unless we were told to land somewhere
    // specific (opening a single file out of a folder).
    int start = result.start;
    if (start == 0) {
        QSettings s;
        start = s.value(m_media ? playlistKey(path) : bookmarkKey(path), 0).toInt();
    }
    m_index = qBound(0, start, m_count - 1);

    pushRecent(path);

    emit titleChanged();
    emit locationChanged();
    emit isArchiveChanged();
    emit countChanged();
    emit generationChanged();
    emit readyChanged();
    emit kindChanged();
    emit indexChanged();
    emit pageNameChanged();
    emit mediaUrlChanged();
    emit mediaSubtitlesChanged();
    emit fontDirsChanged();
    emit opened();
}

// ----------------------------------------------------------------- video ----

QString Book::mediaUrl() const
{
    if (!m_media || m_index < 0 || m_index >= m_media->count())
        return {};
    return m_media->entries().at(m_index).url;
}

QVariantList Book::mediaSubtitles() const
{
    QVariantList out;
    if (!m_media || m_index < 0 || m_index >= m_media->count())
        return out;
    for (const SubtitleRef &sub : m_media->entries().at(m_index).subtitles) {
        QVariantMap map;
        map.insert(u"url"_s, sub.url);
        map.insert(u"title"_s, sub.title);
        map.insert(u"lang"_s, sub.lang);
        map.insert(u"rank"_s, sub.rank);
        out.append(map);
    }
    return out;
}

QStringList Book::fontDirs() const
{
    return m_media ? m_media->fontDirs() : QStringList();
}

void Book::rememberMediaTime(double seconds, double duration)
{
    const QString url = mediaUrl();
    if (url.isEmpty())
        return;
    QSettings s;
    // Finishing an episode should not reopen it three seconds from the end
    // forever -- the same rule rememberPosition() applies to a finished book --
    // and a few seconds in is not a position worth keeping either.
    const bool finished = duration > 0 && seconds >= duration * kResumeTailFraction;
    if (seconds < kResumeFloor || finished)
        s.remove(resumeKey(url));
    else
        s.setValue(resumeKey(url), seconds);
}

double Book::mediaResumeTime() const
{
    const QString url = mediaUrl();
    if (url.isEmpty())
        return 0;
    return QSettings().value(resumeKey(url), 0.0).toDouble();
}

void Book::close()
{
    rememberPosition();
    m_store.set(nullptr);
    m_generation = m_store.generation();
    m_media.reset();
    m_kind = NothingOpen;
    m_title.clear();
    m_location.clear();
    m_count = 0;
    m_index = 0;
    m_isArchive = false;
    emit titleChanged();
    emit locationChanged();
    emit isArchiveChanged();
    emit countChanged();
    emit generationChanged();
    emit readyChanged();
    emit kindChanged();
    emit indexChanged();
    emit pageNameChanged();
    emit mediaUrlChanged();
    emit mediaSubtitlesChanged();
    emit fontDirsChanged();
}

void Book::setIndex(int i)
{
    if (m_count <= 0)
        return;
    const int clamped = qBound(0, i, m_count - 1);
    if (clamped == m_index)
        return;
    m_index = clamped;
    emit indexChanged();
    emit pageNameChanged();
    if (m_media) {
        emit mediaUrlChanged();
        emit mediaSubtitlesChanged();
    }
}

void Book::next()     { setIndex(m_index + 1); }
void Book::previous() { setIndex(m_index - 1); }
void Book::first()    { setIndex(0); }
void Book::last()     { setIndex(m_count - 1); }

void Book::setRightToLeft(bool rtl)
{
    if (rtl == m_rightToLeft)
        return;
    m_rightToLeft = rtl;
    QSettings().setValue(u"rightToLeft"_s, rtl);
    emit rightToLeftChanged();
}

void Book::setFitMode(int mode)
{
    if (mode == m_fitMode)
        return;
    m_fitMode = mode;
    QSettings().setValue(u"fitMode"_s, mode);
    emit fitModeChanged();
}

void Book::clearError()
{
    if (m_error.isEmpty())
        return;
    m_error.clear();
    emit errorChanged();
}

void Book::rememberPosition() const
{
    if (m_location.isEmpty() || m_count <= 0)
        return;
    QSettings s;
    // A page number and an episode number are not the same thing, and the same
    // folder can be read both ways -- a comic folder with a trailer dropped in
    // it opens as a one-entry playlist. Keeping them under separate prefixes
    // stops episode 0 of that playlist from erasing the page you were on.
    const QString key = m_media ? playlistKey(m_location) : bookmarkKey(m_location);
    // Finishing a book should not reopen it on the last page forever.
    if (m_index >= m_count - 1)
        s.remove(key);
    else
        s.setValue(key, m_index);
}

void Book::pushRecent(const QString &path)
{
    m_recent.removeAll(path);
    m_recent.prepend(path);
    while (m_recent.size() > kMaxRecent)
        m_recent.removeLast();
    QSettings().setValue(u"recent"_s, m_recent);
    emit recentChanged();
}

void Book::forgetRecent()
{
    m_recent.clear();
    QSettings().setValue(u"recent"_s, m_recent);
    emit recentChanged();
}
