#include "pageprovider.h"

#include <QBuffer>
#include <QImageReader>
#include <QQuickTextureFactory>
#include <QRunnable>
#include <QThread>

namespace {

// Full-resolution ceiling for a single page. Scans this large are vanishingly
// rare; the cap exists so one pathological file cannot eat a gigabyte of RAM.
constexpr int kMaxEdge = 8000;

class PageResponse : public QQuickImageResponse, public QRunnable
{
public:
    PageResponse(std::shared_ptr<PageSource> source, int index, QSize requested, bool thumbnail)
        : m_source(std::move(source))
        , m_index(index)
        , m_requested(requested)
        , m_thumbnail(thumbnail)
    {
        setAutoDelete(false); // the QML engine owns this object
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override { return m_error; }

    void run() override
    {
        decode();
        emit finished();
    }

private:
    void decode()
    {
        if (!m_source) {
            m_error = QStringLiteral("page belongs to a book that is no longer open");
            return;
        }
        const QByteArray bytes = m_source->read(m_index);
        if (bytes.isEmpty()) {
            m_error = QStringLiteral("could not read page %1").arg(m_index + 1);
            return;
        }

        QBuffer buffer;
        buffer.setData(bytes);
        buffer.open(QIODevice::ReadOnly);

        QImageReader reader(&buffer);
        reader.setAutoTransform(true); // honour the EXIF orientation of camera photos
        reader.setAllocationLimit(1024);

        const QSize full = reader.size();
        const QSize target = scaledSize(full);
        if (target.isValid() && !target.isEmpty() && target != full)
            reader.setScaledSize(target);

        m_image = reader.read();
        if (m_image.isNull())
            m_error = reader.errorString();
    }

    // Thumbnails decode straight to the grid's cell size, which is far cheaper
    // than decoding a 20 MP page and throwing 99% of it away. Full pages only
    // scale when they are absurdly large.
    QSize scaledSize(const QSize &full) const
    {
        if (!full.isValid() || full.isEmpty())
            return {};

        if (m_thumbnail) {
            const int box = qMax(64, qMax(m_requested.width(), m_requested.height()));
            if (full.width() <= box && full.height() <= box)
                return full;
            return full.scaled(box, box, Qt::KeepAspectRatio);
        }

        const int longEdge = qMax(full.width(), full.height());
        if (longEdge <= kMaxEdge)
            return full;
        return full.scaled(kMaxEdge, kMaxEdge, Qt::KeepAspectRatio);
    }

    std::shared_ptr<PageSource> m_source;
    int m_index;
    QSize m_requested;
    bool m_thumbnail;
    QImage m_image;
    QString m_error;
};

} // namespace

PageProvider::PageProvider(PageStore *store, bool thumbnail)
    : m_store(store)
    , m_thumbnail(thumbnail)
{
    // Decoding is CPU-bound. Leave a core for the UI, and keep thumbnail work
    // from crowding out the page the reader is actually waiting on.
    const int cores = qMax(1, QThread::idealThreadCount() - 1);
    m_pool.setMaxThreadCount(thumbnail ? qMax(1, cores / 2) : cores);
}

QQuickImageResponse *PageProvider::requestImageResponse(const QString &id, const QSize &requestedSize)
{
    // id is "<generation>/<index>"
    const qsizetype slash = id.indexOf(u'/');
    const int generation = slash < 0 ? -1 : id.left(slash).toInt();
    const int index = slash < 0 ? -1 : id.mid(slash + 1).toInt();

    auto *response = new PageResponse(m_store->get(generation), index, requestedSize, m_thumbnail);
    m_pool.start(response);
    return response;
}
