#include "book.h"

#include <QCryptographicHash>
#include <QFutureWatcher>
#include <QDir>
#include <QFileInfo>
#include <QPointer>
#include <QSettings>
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

constexpr int kMaxRecent = 24;
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
        int start = 0;
        QString error;
        std::shared_ptr<PageSource> source = PageSource::open(absolute, &start, &error);
        return std::make_tuple(source, start, error);
    });

    auto *watcher = new QFutureWatcher<std::tuple<std::shared_ptr<PageSource>, int, QString>>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [self, watcher, token] {
        const auto [source, start, error] = watcher->result();
        watcher->deleteLater();
        if (!self || token != self->m_openToken)
            return; // a newer open won the race
        self->adopt(source, start, error);
    });
    watcher->setFuture(future);
}

void Book::adopt(std::shared_ptr<PageSource> source, int startIndex, const QString &error)
{
    m_busy = false;
    emit busyChanged();

    if (!source) {
        m_error = error.isEmpty() ? u"could not open that"_s : error;
        emit errorChanged();
        return;
    }

    const QString path = source->location();
    m_title = source->title();
    m_location = path;
    m_isArchive = source->isArchive();
    m_count = source->count();

    m_store.set(std::move(source));
    m_generation = m_store.generation();

    // Resume where this book was left, unless we were told to land on a
    // specific image (opening a single file from a folder).
    int start = startIndex;
    if (start == 0) {
        QSettings s;
        start = s.value(bookmarkKey(path), 0).toInt();
    }
    m_index = qBound(0, start, m_count - 1);

    pushRecent(path);

    emit titleChanged();
    emit locationChanged();
    emit isArchiveChanged();
    emit countChanged();
    emit generationChanged();
    emit readyChanged();
    emit indexChanged();
    emit pageNameChanged();
    emit opened();
}

void Book::close()
{
    rememberPosition();
    m_store.set(nullptr);
    m_generation = m_store.generation();
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
    emit indexChanged();
    emit pageNameChanged();
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
    // Finishing a book should not reopen it on the last page forever.
    if (m_index >= m_count - 1)
        s.remove(bookmarkKey(m_location));
    else
        s.setValue(bookmarkKey(m_location), m_index);
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
