#pragma once

#include "book.h"

#include <QQuickAsyncImageProvider>
#include <QThreadPool>

// Serves decoded pages to QML.
//
// Two providers are registered: "page" hands back the image at full resolution
// for the reader, "thumb" decodes straight to the requested size for the grid.
// Both take URLs shaped image://<id>/<generation>/<index>; the generation is the
// book identity, so a URL minted for the previous book simply fails instead of
// returning someone else's page out of Qt's pixmap cache.
class PageProvider : public QQuickAsyncImageProvider
{
public:
    PageProvider(PageStore *store, bool thumbnail);
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

private:
    PageStore *m_store;
    bool m_thumbnail;
    QThreadPool m_pool;
};
