#include "source.h"
#include "naturalsort.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QSet>

#include <algorithm>

#include <archive.h>
#include <archive_entry.h>

using namespace Qt::StringLiterals;

QStringList PageSource::imageSuffixes()
{
    // Whatever Qt's plugins report, which on a full install covers avif, heif,
    // jxl, psd, exr, raw and friends as well as the obvious ones.
    static const QStringList list = [] {
        QSet<QString> set;
        for (const QByteArray &fmt : QImageReader::supportedImageFormats())
            set.insert(QString::fromLatin1(fmt).toLower());
        // A few extensions whose plugin advertises a different format name.
        set.unite({ u"jpe"_s, u"jfif"_s, u"heic"_s, u"heif"_s, u"avifs"_s });
        QStringList out(set.begin(), set.end());
        out.sort();
        return out;
    }();
    return list;
}

QStringList PageSource::archiveSuffixes()
{
    return { u"zip"_s, u"cbz"_s, u"rar"_s, u"cbr"_s, u"7z"_s, u"cb7"_s,
             u"tar"_s, u"cbt"_s };
}

bool PageSource::isImageFile(const QString &name)
{
    const QString suffix = QFileInfo(name).suffix().toLower();
    return !suffix.isEmpty() && imageSuffixes().contains(suffix);
}

bool PageSource::isArchiveFile(const QString &name)
{
    return archiveSuffixes().contains(QFileInfo(name).suffix().toLower());
}

// ---------------------------------------------------------------- folder ----

FolderSource::FolderSource(const QString &dir)
    : m_dir(QDir(dir).absolutePath())
{
    QDir d(m_dir);
    if (!d.exists())
        return;

    const QFileInfoList files = d.entryInfoList(QDir::Files | QDir::Readable, QDir::NoSort);
    for (const QFileInfo &fi : files) {
        if (fi.fileName().startsWith(u'.'))
            continue;
        if (!isImageFile(fi.fileName()))
            continue;
        PageEntry e;
        e.name = fi.fileName();
        e.display = fi.fileName();
        e.size = fi.size();
        m_entries.append(e);
    }

    std::sort(m_entries.begin(), m_entries.end(),
              [](const PageEntry &a, const PageEntry &b) { return naturalLess(a.name, b.name); });

    m_title = d.dirName().isEmpty() ? m_dir : d.dirName();
    m_location = m_dir;
    m_valid = !m_entries.isEmpty();
}

QByteArray FolderSource::read(int index)
{
    if (index < 0 || index >= m_entries.size())
        return {};
    QFile f(filePath(index));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return f.readAll();
}

QString FolderSource::filePath(int index) const
{
    if (index < 0 || index >= m_entries.size())
        return {};
    return m_dir + u'/' + m_entries.at(index).name;
}

int FolderSource::indexOfFile(const QString &absolutePath) const
{
    const QString name = QFileInfo(absolutePath).fileName();
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries.at(i).name == name)
            return i;
    }
    return -1;
}

// --------------------------------------------------------------- archive ----

namespace {

archive *newReader()
{
    archive *a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);
    return a;
}

QString entryName(archive_entry *e)
{
    if (const char *utf8 = archive_entry_pathname_utf8(e))
        return QString::fromUtf8(utf8);
    if (const char *raw = archive_entry_pathname(e))
        return QString::fromLocal8Bit(raw);
    return {};
}

// Archive members that are never pages: macOS resource forks, hidden files and
// the stray ReadMe.txt that scanlation groups drop in every release.
bool isJunk(const QString &name)
{
    if (name.startsWith(u"__MACOSX/"_s) || name.contains(u"/._"_s) || name.startsWith(u"._"_s))
        return true;
    const QString base = name.section(u'/', -1);
    return base.isEmpty() || base.startsWith(u'.');
}

} // namespace

ArchiveSource::ArchiveSource(const QString &path)
    : m_path(path)
{
    archive *a = newReader();
    if (archive_read_open_filename(a, QFile::encodeName(path).constData(), 1 << 17) != ARCHIVE_OK) {
        m_error = QString::fromUtf8(archive_error_string(a));
        archive_read_free(a);
        return;
    }

    archive_entry *entry = nullptr;
    int ordinal = 0;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        const QString name = entryName(entry);
        const int thisOrdinal = ordinal++;
        if (archive_entry_filetype(entry) == AE_IFDIR)
            continue;
        if (isJunk(name) || !isImageFile(name))
            continue;
        PageEntry e;
        e.name = name;
        e.display = name.section(u'/', -1);
        e.size = archive_entry_size(entry);
        e.ordinal = thisOrdinal;
        m_entries.append(e);
    }
    archive_read_free(a);

    std::sort(m_entries.begin(), m_entries.end(),
              [](const PageEntry &a, const PageEntry &b) { return naturalLess(a.name, b.name); });

    m_title = QFileInfo(path).completeBaseName();
    m_location = QFileInfo(path).absoluteFilePath();
    m_valid = !m_entries.isEmpty();
    if (!m_valid && m_error.isEmpty())
        m_error = QStringLiteral("no images found in this archive");
}

ArchiveSource::~ArchiveSource()
{
    QMutexLocker lock(&m_mutex);
    closeHandle();
}

void ArchiveSource::closeHandle()
{
    if (m_handle) {
        archive_read_free(m_handle);
        m_handle = nullptr;
    }
    m_position = -1;
}

bool ArchiveSource::rewind()
{
    closeHandle();
    m_handle = newReader();
    if (archive_read_open_filename(m_handle, QFile::encodeName(m_path).constData(), 1 << 17) != ARCHIVE_OK) {
        archive_read_free(m_handle);
        m_handle = nullptr;
        return false;
    }
    return true;
}

QByteArray ArchiveSource::read(int index)
{
    if (index < 0 || index >= m_entries.size())
        return {};
    const PageEntry wanted = m_entries.at(index);

    QMutexLocker lock(&m_mutex);

    // Going backwards (or starting cold) means starting the stream over.
    if (!m_handle || m_position >= wanted.ordinal) {
        if (!rewind())
            return {};
    }

    archive_entry *entry = nullptr;
    while (archive_read_next_header(m_handle, &entry) == ARCHIVE_OK) {
        ++m_position;
        if (m_position != wanted.ordinal)
            continue;

        const qint64 hint = archive_entry_size_is_set(entry) ? archive_entry_size(entry) : 0;
        QByteArray data;
        data.reserve(hint > 0 ? hint : 1 << 18);
        char buf[1 << 16];
        for (;;) {
            const la_ssize_t n = archive_read_data(m_handle, buf, sizeof(buf));
            if (n < 0) {          // corrupt member: give up on this page only
                closeHandle();
                return {};
            }
            if (n == 0)
                break;
            data.append(buf, int(n));
        }
        return data;
    }

    // Ran off the end without finding it -- the archive changed under us.
    closeHandle();
    return {};
}

// ------------------------------------------------------------------ open ----

std::unique_ptr<PageSource> PageSource::open(const QString &path, int *startIndex, QString *error)
{
    if (startIndex)
        *startIndex = 0;
    const QFileInfo info(path);
    if (!info.exists()) {
        if (error)
            *error = QStringLiteral("no such file or folder");
        return nullptr;
    }

    if (info.isDir()) {
        auto src = std::make_unique<FolderSource>(info.absoluteFilePath());
        if (!src->isValid()) {
            if (error)
                *error = QStringLiteral("no images in this folder");
            return nullptr;
        }
        return src;
    }

    if (isArchiveFile(info.fileName())) {
        auto src = std::make_unique<ArchiveSource>(info.absoluteFilePath());
        if (!src->isValid()) {
            if (error)
                *error = src->error();
            return nullptr;
        }
        return src;
    }

    if (isImageFile(info.fileName())) {
        // Opening one picture opens its folder, so left/right still works.
        auto src = std::make_unique<FolderSource>(info.absolutePath());
        if (!src->isValid()) {
            if (error)
                *error = QStringLiteral("could not read that image");
            return nullptr;
        }
        if (startIndex)
            *startIndex = qMax(0, src->indexOfFile(info.absoluteFilePath()));
        return src;
    }

    if (error)
        *error = QStringLiteral("not an image or a comic archive");
    return nullptr;
}
