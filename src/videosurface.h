#pragma once

#include <QQmlEngine>
#include <QQuickFramebufferObject>

// The video, as an ordinary item in the scene graph.
//
// mpv is asked to render into a framebuffer object that Qt then composites like
// any other texture, which is the whole point: the bars, the sheets and the
// gesture overlays are QML drawn *over* the picture, with real z-order and
// opacity. Handing mpv a native window instead (--wid) would put an opaque
// child HWND on top of the scene and none of that would be possible.
//
// This costs an OpenGL scene graph: main.cpp pins the RHI backend to OpenGL
// before the engine loads, because mpv's render API speaks GL and Qt would
// otherwise pick Direct3D on Windows.
class VideoSurface : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit VideoSurface(QQuickItem *parent = nullptr);

    Renderer *createRenderer() const override;

signals:
    // Emitted from mpv's render thread when a new frame is ready. It is
    // connected to update() as a queued connection, so the actual repaint is
    // requested on the thread that owns the item.
    void frameReady();
};
