#pragma once

#include <QByteArray>
#include <QMutex>
#include <QString>
#include <QStringList>
#include <QVector>

#include <memory>

struct archive;

// One readable page.
struct PageEntry {
    QString name;      // path as it appears in the folder or archive
    QString display;   // basename, what the UI shows
    qint64 size = 0;
    int ordinal = 0;   // position in the archive's own entry order (archives only)
};

// A flat, ordered list of images that came from somewhere -- a directory or a
// comic archive. Subclasses only have to enumerate and hand back bytes; the
// decoding, caching and prefetching all happen above this layer.
//
// read() is called from decoder threads, so it must be safe to call
// concurrently. The archive implementation serialises internally.
class PageSource
{
public:
    virtual ~PageSource() = default;

    const QVector<PageEntry> &entries() const { return m_entries; }
    int count() const { return m_entries.size(); }

    virtual QByteArray read(int index) = 0;

    // Absolute filesystem path of a page, or an empty string when the page only
    // exists inside an archive.
    virtual QString filePath(int) const { return {}; }

    QString title() const { return m_title; }
    QString location() const { return m_location; }
    virtual bool isArchive() const = 0;

    // Suffixes we are willing to open, derived from what Qt can actually decode
    // on this machine plus the archive-ish ones we handle ourselves.
    static QStringList imageSuffixes();
    static QStringList archiveSuffixes();
    static bool isImageFile(const QString &name);
    static bool isArchiveFile(const QString &name);

    // Opens whatever `path` points at: a directory, an archive, or a single
    // image (which opens its whole folder, positioned on that image).
    // `startIndex` receives the page to land on. Returns null on failure.
    static std::unique_ptr<PageSource> open(const QString &path, int *startIndex, QString *error);

protected:
    QVector<PageEntry> m_entries;
    QString m_title;
    QString m_location;
};

// A directory of images. Non-recursive by default: a comic folder is flat, and
// recursing would silently merge unrelated chapters.
class FolderSource : public PageSource
{
public:
    explicit FolderSource(const QString &dir);
    QByteArray read(int index) override;
    QString filePath(int index) const override;
    bool isArchive() const override { return false; }
    bool isValid() const { return m_valid; }
    int indexOfFile(const QString &absolutePath) const;

private:
    QString m_dir;
    bool m_valid = false;
};

// A zip/cbz/rar/cbr/7z/tar archive, read through libarchive.
//
// libarchive is a streaming reader: there is no seek-to-entry. Random access
// would mean reopening and re-walking for every page. Since reading a comic is
// overwhelmingly forward-sequential, this keeps one open handle parked at the
// last entry it read and simply continues from there; it only reopens when asked
// to go backwards. That also keeps solid archives (7z, solid rar), which *must*
// be decompressed in order, fast rather than quadratic.
class ArchiveSource : public PageSource
{
public:
    explicit ArchiveSource(const QString &path);
    ~ArchiveSource() override;

    QByteArray read(int index) override;
    bool isArchive() const override { return true; }
    bool isValid() const { return m_valid; }
    QString error() const { return m_error; }

private:
    bool rewind();
    void closeHandle();

    QString m_path;
    bool m_valid = false;
    QString m_error;

    QMutex m_mutex;
    archive *m_handle = nullptr;
    int m_position = -1; // ordinal of the entry the handle is parked on
};
