#include "videosurface.h"
#include "player.h"

#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QQuickWindow>

#include <mpv/client.h>
#include <mpv/render_gl.h>

namespace {

// mpv resolves GL entry points through this rather than linking them, so it
// works against whatever context Qt happened to create.
void *getProcAddress(void *, const char *name)
{
    QOpenGLContext *context = QOpenGLContext::currentContext();
    if (!context)
        return nullptr;
    return reinterpret_cast<void *>(context->getProcAddress(QByteArray(name)));
}

// Everything in here runs on the scene graph render thread, with the GL context
// current. That is the only thread allowed to touch the render context, which
// is why it is created on the first render() and destroyed in the destructor
// rather than anywhere more obvious.
class SurfaceRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit SurfaceRenderer(VideoSurface *surface)
        : m_surface(surface)
    {
    }

    ~SurfaceRenderer() override
    {
        if (m_context) {
            // Drop the callback before tearing the context down, so a frame
            // arriving right now cannot reach a half-destroyed object.
            mpv_render_context_set_update_callback(m_context, nullptr, nullptr);
            mpv_render_context_free(m_context);
            m_context = nullptr;
        }
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        // No depth or stencil: mpv draws a flat picture and nothing else is
        // rendered into this buffer.
        QOpenGLFramebufferObjectFormat format;
        format.setAttachment(QOpenGLFramebufferObject::NoAttachment);
        return new QOpenGLFramebufferObject(size, format);
    }

    void render() override
    {
        if (!ensureContext())
            return;

        QOpenGLFramebufferObject *fbo = framebufferObject();
        if (!fbo)
            return;

        mpv_opengl_fbo target{ int(fbo->handle()), fbo->width(), fbo->height(), 0 };
        // Qt's framebuffers are bottom-up as far as GL is concerned, so mpv is
        // asked to flip rather than the item being mirrored afterwards.
        int flip = 1;
        mpv_render_param params[] = {
            { MPV_RENDER_PARAM_OPENGL_FBO, &target },
            { MPV_RENDER_PARAM_FLIP_Y, &flip },
            { MPV_RENDER_PARAM_INVALID, nullptr },
        };

        // mpv issues its own GL commands and leaves its own state behind. The
        // begin/end pair tells Qt's renderer to assume nothing survived.
        QQuickWindow *window = m_surface ? m_surface->window() : nullptr;
        if (window)
            window->beginExternalCommands();
        mpv_render_context_render(m_context, params);
        if (window)
            window->endExternalCommands();
    }

private:
    bool ensureContext()
    {
        if (m_context)
            return true;
        if (m_failed)
            return false;

        Player *player = Player::instance();
        mpv_handle *mpv = player ? player->handle() : nullptr;
        if (!mpv)
            return false; // nothing opened yet; there is simply nothing to draw

        mpv_opengl_init_params gl{ getProcAddress, nullptr };
        int advanced = 0;
        mpv_render_param params[] = {
            { MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL) },
            { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl },
            { MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced },
            { MPV_RENDER_PARAM_INVALID, nullptr },
        };

        if (mpv_render_context_create(&m_context, mpv, params) < 0) {
            m_context = nullptr;
            m_failed = true; // do not retry every frame
            qWarning("mpv: could not create an OpenGL render context");
            return false;
        }

        // The callback fires on whichever thread decoded the frame. Emitting a
        // signal is the safe thing to do from there: the connection to update()
        // is queued, so the repaint is requested on the item's own thread.
        mpv_render_context_set_update_callback(m_context, [](void *ctx) {
            auto *surface = static_cast<VideoSurface *>(ctx);
            emit surface->frameReady();
        }, m_surface);

        return true;
    }

    VideoSurface *m_surface = nullptr;
    mpv_render_context *m_context = nullptr;
    bool m_failed = false;
};

} // namespace

VideoSurface::VideoSurface(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
{
    connect(this, &VideoSurface::frameReady,
            this, [this] { update(); }, Qt::QueuedConnection);
}

QQuickFramebufferObject::Renderer *VideoSurface::createRenderer() const
{
    return new SurfaceRenderer(const_cast<VideoSurface *>(this));
}
