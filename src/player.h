#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

struct mpv_handle;

// The video half of r9view: a typed, Qt-shaped wrapper over libmpv.
//
// mpv is driven entirely from here. It is created with vo=libmpv and with its
// own on-screen controller and key handling switched off, because the interface
// is r9view's -- written in QML, sized for a fingertip, and drawn over the video
// by the scene graph. Everything the UI needs is a Q_PROPERTY or a Q_INVOKABLE;
// nothing reaches into the mpv handle from outside this class.
//
// libmpv is created lazily, on the first file opened, so that someone who only
// ever reads comics never pays to start a media player they did not ask for.
//
// Threading: libmpv calls its wakeup callback from its own thread. That callback
// does nothing but post to this object, and every mpv_* call other than the
// wakeup itself happens on the GUI thread. The one exception is the render
// context, which belongs to the scene graph render thread and lives in
// videosurface.cpp.
class Player : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // One notify signal per property. book.h explains why at length and the
    // reasoning applies just as much here: QML re-evaluates a binding only for
    // the property it hooked, so a shared signal silently strands the others.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(double position READ position WRITE setPosition NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(double speed READ speed WRITE setSpeed NOTIFY speedChanged)
    Q_PROPERTY(QString mediaTitle READ mediaTitle NOTIFY mediaTitleChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY bufferingChanged)
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY hasVideoChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

    // Track lists are handed to QML as lists of plain objects, so a delegate can
    // read t.id, t.title, t.lang, t.codec, t.external and t.selected directly.
    Q_PROPERTY(QVariantList audioTracks READ audioTracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList subtitleTracks READ subtitleTracks NOTIFY tracksChanged)
    Q_PROPERTY(int audioTrack READ audioTrack WRITE setAudioTrack NOTIFY audioTrackChanged)
    Q_PROPERTY(int subtitleTrack READ subtitleTrack WRITE setSubtitleTrack NOTIFY subtitleTrackChanged)
    Q_PROPERTY(double subDelay READ subDelay WRITE setSubDelay NOTIFY subDelayChanged)
    Q_PROPERTY(bool subtitleVisible READ subtitleVisible WRITE setSubtitleVisible NOTIFY subtitleVisibleChanged)

    // Driven by gestures: a vertical drag on the left of the picture changes
    // brightness, and a pinch zooms. Both are mpv's own -- zooming the picture
    // rather than scaling the item keeps it sharp, because mpv rescales from the
    // decoded frame instead of stretching a texture.
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(double videoZoom READ videoZoom WRITE setVideoZoom NOTIFY videoZoomChanged)

public:
    explicit Player(QObject *parent = nullptr);
    ~Player() override;

    // There is exactly one Player -- QML_SINGLETON guarantees it. The render
    // surface lives in the scene graph, well out of reach of a QML binding,
    // so it finds the handle through here rather than having one passed in.
    static Player *instance();

    // The handle the render surface needs. Null until the first open().
    mpv_handle *handle() const { return m_mpv; }

    bool available() const { return m_available; }
    bool ready() const { return m_ready; }
    bool paused() const { return m_paused; }
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool seekable() const { return m_seekable; }
    double volume() const { return m_volume; }
    bool muted() const { return m_muted; }
    double speed() const { return m_speed; }
    QString mediaTitle() const { return m_mediaTitle; }
    bool buffering() const { return m_buffering; }
    bool hasVideo() const { return m_hasVideo; }
    QString error() const { return m_error; }
    QVariantList audioTracks() const { return m_audioTracks; }
    QVariantList subtitleTracks() const { return m_subtitleTracks; }
    int audioTrack() const { return m_audioTrack; }
    int subtitleTrack() const { return m_subtitleTrack; }
    double subDelay() const { return m_subDelay; }
    bool subtitleVisible() const { return m_subtitleVisible; }
    int brightness() const { return m_brightness; }
    double videoZoom() const { return m_videoZoom; }

    void setPaused(bool paused);
    void setPosition(double seconds);
    void setVolume(double volume);
    void setMuted(bool muted);
    void setSpeed(double speed);
    void setAudioTrack(int id);
    void setSubtitleTrack(int id);
    void setSubDelay(double seconds);
    void setSubtitleVisible(bool visible);
    void setBrightness(int value);
    void setVideoZoom(double value);

    // `url` is either a plain filesystem path or, for a member of an archive,
    // an archive://<archive>|<entry> URL. mpv is linked against libarchive and
    // reads and seeks both without anything being unpacked first.
    Q_INVOKABLE void open(const QString &url);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void seekBy(double seconds);
    Q_INVOKABLE void seekTo(double seconds);
    Q_INVOKABLE void frameStep(int direction);
    Q_INVOKABLE void addSubtitle(const QString &url, const QString &title = {}, const QString &lang = {});
    // mpv's own cycle command. Keeping it generic is what lets the keyboard
    // bindings stay a one-line mapping instead of a method per property.
    Q_INVOKABLE void cycle(const QString &property, bool reverse = false);
    Q_INVOKABLE void screenshot();
    Q_INVOKABLE void clearError();

    // Formats seconds as h:mm:ss (or m:ss under an hour) for the bars.
    Q_INVOKABLE static QString formatTime(double seconds);

    // Called by the render surface once its mpv render context exists, and
    // again if it goes away. vo=libmpv refuses to initialise without one, so a
    // file opened before the surface is up would fail outright -- open() holds
    // the URL until this says the scene graph is ready for it.
    void notifyRenderContext(bool ready);

signals:
    void availableChanged();
    void readyChanged();
    void pausedChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void volumeChanged();
    void mutedChanged();
    void speedChanged();
    void mediaTitleChanged();
    void bufferingChanged();
    void hasVideoChanged();
    void errorChanged();
    void tracksChanged();
    void audioTrackChanged();
    void subtitleTrackChanged();
    void subDelayChanged();
    void subtitleVisibleChanged();
    void brightnessChanged();
    void videoZoomChanged();

    // The render surface watches this: the handle it renders through only
    // exists once a file has been opened.
    void handleChanged();
    // A file finished on its own, as opposed to being stopped.
    void endOfFile();
    void fileLoaded();

private:
    bool ensureMpv();          // create and initialise libmpv on first use
    void pumpEvents();         // drain mpv's queue on the GUI thread
    void readTracks();
    void flushPendingOpen();

    mpv_handle *m_mpv = nullptr;
    bool m_available = false;
    bool m_ready = false;
    bool m_paused = false;
    double m_position = 0;
    double m_duration = 0;
    bool m_seekable = false;
    double m_volume = 100;
    bool m_muted = false;
    double m_speed = 1.0;
    QString m_mediaTitle;
    bool m_buffering = false;
    bool m_hasVideo = false;
    QString m_error;
    QVariantList m_audioTracks;
    QVariantList m_subtitleTracks;
    int m_audioTrack = 0;
    int m_subtitleTrack = 0;
    double m_subDelay = 0;
    bool m_subtitleVisible = true;
    int m_brightness = 0;
    double m_videoZoom = 0;
    QString m_pendingUrl;
    bool m_renderReady = false;
};
