#include "player.h"

#include <QMetaObject>
#include <QVariantMap>

#include <mpv/client.h>

using namespace Qt::StringLiterals;

namespace {

// mpv hands structured data back as a tree of mpv_node. Only the shapes that
// actually turn up in the properties r9view observes are translated; anything
// else becomes an invalid QVariant rather than a guess.
QVariant nodeToVariant(const mpv_node *node)
{
    switch (node->format) {
    case MPV_FORMAT_STRING:
        return QString::fromUtf8(node->u.string);
    case MPV_FORMAT_FLAG:
        return node->u.flag != 0;
    case MPV_FORMAT_INT64:
        return qlonglong(node->u.int64);
    case MPV_FORMAT_DOUBLE:
        return node->u.double_;
    case MPV_FORMAT_NODE_ARRAY: {
        QVariantList list;
        for (int i = 0; i < node->u.list->num; ++i)
            list.append(nodeToVariant(&node->u.list->values[i]));
        return list;
    }
    case MPV_FORMAT_NODE_MAP: {
        QVariantMap map;
        for (int i = 0; i < node->u.list->num; ++i)
            map.insert(QString::fromUtf8(node->u.list->keys[i]),
                       nodeToVariant(&node->u.list->values[i]));
        return map;
    }
    default:
        return {};
    }
}

// Properties worth watching. Every one of these drives something visible, so
// the list doubles as the answer to "what can the interface show".
struct Observed {
    const char *name;
    mpv_format format;
};

constexpr Observed kObserved[] = {
    { "pause",            MPV_FORMAT_FLAG },
    { "time-pos",         MPV_FORMAT_DOUBLE },
    { "duration",         MPV_FORMAT_DOUBLE },
    { "seekable",         MPV_FORMAT_FLAG },
    { "volume",           MPV_FORMAT_DOUBLE },
    { "mute",             MPV_FORMAT_FLAG },
    { "speed",            MPV_FORMAT_DOUBLE },
    { "media-title",      MPV_FORMAT_STRING },
    { "paused-for-cache", MPV_FORMAT_FLAG },
    { "track-list",       MPV_FORMAT_NODE },
    { "aid",              MPV_FORMAT_INT64 },
    { "sid",              MPV_FORMAT_INT64 },
    { "sub-delay",        MPV_FORMAT_DOUBLE },
    { "video-params/w",   MPV_FORMAT_INT64 },
};

} // namespace

// ---------------------------------------------------------------- lifetime ----

namespace { Player *g_instance = nullptr; }

Player *Player::instance() { return g_instance; }

Player::Player(QObject *parent)
    : QObject(parent)
{
    g_instance = this;
}

Player::~Player()
{
    if (g_instance == this)
        g_instance = nullptr;
    if (m_mpv) {
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
    }
}

bool Player::ensureMpv()
{
    if (m_mpv)
        return true;

    m_mpv = mpv_create();
    if (!m_mpv) {
        m_error = u"could not start the media player"_s;
        emit errorChanged();
        return false;
    }

    // Options that have to be set before mpv_initialize.
    //
    // vo=libmpv is what lets the scene graph render the video itself. The
    // user's own mpv.conf is deliberately not read: r9view draws its own
    // controls, and a stray vo= or osc= in a config file would fight them.
    mpv_set_option_string(m_mpv, "config", "no");
    mpv_set_option_string(m_mpv, "terminal", "no");
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    mpv_set_option_string(m_mpv, "osc", "no");
    mpv_set_option_string(m_mpv, "osd-level", "0");
    mpv_set_option_string(m_mpv, "input-default-bindings", "no");
    mpv_set_option_string(m_mpv, "input-vo-keyboard", "no");
    mpv_set_option_string(m_mpv, "ytdl", "no");
    mpv_set_option_string(m_mpv, "idle", "yes");
    // Hold the last frame rather than tearing everything down at the end, so
    // the interface can offer the next episode over a still picture.
    mpv_set_option_string(m_mpv, "keep-open", "yes");
    // auto-copy rather than auto-safe: frames have to come back to system
    // memory to reach an OpenGL FBO. Measured as d3d11va-copy on this machine,
    // which decodes 10-bit HEVC without breaking a sweat.
    mpv_set_option_string(m_mpv, "hwdec", "auto-copy");
    // Subtitles sitting next to the video are mpv's to find. The ones in nested
    // Subs/ folders are ours and get added explicitly -- mpv never looks there.
    mpv_set_option_string(m_mpv, "sub-auto", "fuzzy");
    mpv_set_option_string(m_mpv, "volume-max", "150");

    if (mpv_initialize(m_mpv) < 0) {
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
        m_error = u"could not start the media player"_s;
        emit errorChanged();
        return false;
    }

    mpv_request_log_messages(m_mpv, "warn");

    for (const Observed &o : kObserved)
        mpv_observe_property(m_mpv, 0, o.name, o.format);

    // The wakeup callback runs on an mpv thread and is forbidden from calling
    // back into mpv, so it does exactly one thing: post to this object. The
    // queued call then drains the queue on the GUI thread, where the rest of
    // this class already lives.
    mpv_set_wakeup_callback(m_mpv, [](void *ctx) {
        auto *self = static_cast<Player *>(ctx);
        QMetaObject::invokeMethod(self, [self] { self->pumpEvents(); }, Qt::QueuedConnection);
    }, this);

    m_available = true;
    emit availableChanged();
    emit handleChanged();
    return true;
}

// ------------------------------------------------------------------ events ----

void Player::pumpEvents()
{
    if (!m_mpv)
        return;

    for (;;) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (!event || event->event_id == MPV_EVENT_NONE)
            break;

        switch (event->event_id) {
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *prop = static_cast<mpv_event_property *>(event->data);
            const QLatin1StringView name(prop->name);

            if (name == "pause"_L1 && prop->format == MPV_FORMAT_FLAG) {
                const bool value = *static_cast<int *>(prop->data) != 0;
                if (value != m_paused) { m_paused = value; emit pausedChanged(); }

            } else if (name == "time-pos"_L1) {
                // time-pos goes absent between files. Treating that as zero
                // keeps the scrub bar from sitting wherever it last was.
                const double value = prop->format == MPV_FORMAT_DOUBLE
                                   ? *static_cast<double *>(prop->data) : 0.0;
                if (!qFuzzyCompare(value + 1, m_position + 1)) { m_position = value; emit positionChanged(); }

            } else if (name == "duration"_L1) {
                const double value = prop->format == MPV_FORMAT_DOUBLE
                                   ? *static_cast<double *>(prop->data) : 0.0;
                if (!qFuzzyCompare(value + 1, m_duration + 1)) { m_duration = value; emit durationChanged(); }

            } else if (name == "seekable"_L1 && prop->format == MPV_FORMAT_FLAG) {
                const bool value = *static_cast<int *>(prop->data) != 0;
                if (value != m_seekable) { m_seekable = value; emit seekableChanged(); }

            } else if (name == "volume"_L1 && prop->format == MPV_FORMAT_DOUBLE) {
                const double value = *static_cast<double *>(prop->data);
                if (!qFuzzyCompare(value + 1, m_volume + 1)) { m_volume = value; emit volumeChanged(); }

            } else if (name == "mute"_L1 && prop->format == MPV_FORMAT_FLAG) {
                const bool value = *static_cast<int *>(prop->data) != 0;
                if (value != m_muted) { m_muted = value; emit mutedChanged(); }

            } else if (name == "speed"_L1 && prop->format == MPV_FORMAT_DOUBLE) {
                const double value = *static_cast<double *>(prop->data);
                if (!qFuzzyCompare(value + 1, m_speed + 1)) { m_speed = value; emit speedChanged(); }

            } else if (name == "media-title"_L1) {
                const QString value = prop->format == MPV_FORMAT_STRING
                                    ? QString::fromUtf8(*static_cast<char **>(prop->data)) : QString();
                if (value != m_mediaTitle) { m_mediaTitle = value; emit mediaTitleChanged(); }

            } else if (name == "paused-for-cache"_L1 && prop->format == MPV_FORMAT_FLAG) {
                const bool value = *static_cast<int *>(prop->data) != 0;
                if (value != m_buffering) { m_buffering = value; emit bufferingChanged(); }

            } else if (name == "track-list"_L1) {
                readTracks();

            } else if (name == "aid"_L1) {
                // aid is the string "no", not an integer, when nothing is
                // selected -- hence the format check rather than a blind read.
                const int value = prop->format == MPV_FORMAT_INT64
                                ? int(*static_cast<qint64 *>(prop->data)) : 0;
                if (value != m_audioTrack) { m_audioTrack = value; emit audioTrackChanged(); }

            } else if (name == "sid"_L1) {
                const int value = prop->format == MPV_FORMAT_INT64
                                ? int(*static_cast<qint64 *>(prop->data)) : 0;
                if (value != m_subtitleTrack) { m_subtitleTrack = value; emit subtitleTrackChanged(); }

            } else if (name == "sub-delay"_L1 && prop->format == MPV_FORMAT_DOUBLE) {
                const double value = *static_cast<double *>(prop->data);
                if (!qFuzzyCompare(value + 1, m_subDelay + 1)) { m_subDelay = value; emit subDelayChanged(); }

            } else if (name == "video-params/w"_L1) {
                // The property only has a value once a video stream is
                // decoding, which is exactly the question being asked.
                const bool value = prop->format == MPV_FORMAT_INT64;
                if (value != m_hasVideo) { m_hasVideo = value; emit hasVideoChanged(); }
            }
            break;
        }

        case MPV_EVENT_FILE_LOADED:
            if (!m_ready) { m_ready = true; emit readyChanged(); }
            readTracks();
            emit fileLoaded();
            break;

        case MPV_EVENT_END_FILE: {
            auto *end = static_cast<mpv_event_end_file *>(event->data);
            if (end->reason == MPV_END_FILE_REASON_ERROR) {
                m_error = QString::fromUtf8(mpv_error_string(end->error));
                emit errorChanged();
            }
            if (end->reason == MPV_END_FILE_REASON_EOF)
                emit endOfFile();
            break;
        }

        case MPV_EVENT_LOG_MESSAGE: {
            auto *msg = static_cast<mpv_event_log_message *>(event->data);
            qWarning("mpv/%s: %s", msg->prefix, msg->text);
            break;
        }

        case MPV_EVENT_SHUTDOWN:
            return; // the handle is going away; do not touch it again

        default:
            break;
        }
    }
}

void Player::readTracks()
{
    if (!m_mpv)
        return;

    mpv_node node;
    if (mpv_get_property(m_mpv, "track-list", MPV_FORMAT_NODE, &node) < 0)
        return;
    const QVariant tracks = nodeToVariant(&node);
    mpv_free_node_contents(&node);

    QVariantList audio;
    QVariantList subs;
    for (const QVariant &entry : tracks.toList()) {
        const QVariantMap t = entry.toMap();
        const QString type = t.value(u"type"_s).toString();

        QVariantMap out;
        out.insert(u"id"_s, t.value(u"id"_s).toInt());
        out.insert(u"title"_s, t.value(u"title"_s).toString());
        out.insert(u"lang"_s, t.value(u"lang"_s).toString());
        out.insert(u"codec"_s, t.value(u"codec"_s).toString());
        out.insert(u"external"_s, t.value(u"external"_s).toBool());
        out.insert(u"selected"_s, t.value(u"selected"_s).toBool());
        out.insert(u"isDefault"_s, t.value(u"default"_s).toBool());
        out.insert(u"forced"_s, t.value(u"forced"_s).toBool());
        out.insert(u"filename"_s, t.value(u"external-filename"_s).toString());

        if (type == u"audio"_s)
            audio.append(out);
        else if (type == u"sub"_s)
            subs.append(out);
    }

    if (audio != m_audioTracks || subs != m_subtitleTracks) {
        m_audioTracks = audio;
        m_subtitleTracks = subs;
        emit tracksChanged();
    }
}

// ---------------------------------------------------------------- commands ----

void Player::open(const QString &url)
{
    if (url.isEmpty() || !ensureMpv())
        return;

    const QByteArray target = url.toUtf8();
    const char *args[] = { "loadfile", target.constData(), "replace", nullptr };
    mpv_command(m_mpv, args);
}

void Player::stop()
{
    if (!m_mpv)
        return;
    const char *args[] = { "stop", nullptr };
    mpv_command(m_mpv, args);
    if (m_ready) { m_ready = false; emit readyChanged(); }
}

void Player::togglePause()
{
    setPaused(!m_paused);
}

void Player::seekBy(double seconds)
{
    if (!m_mpv)
        return;
    const QByteArray amount = QByteArray::number(seconds, 'f', 3);
    const char *args[] = { "seek", amount.constData(), "relative", nullptr };
    mpv_command(m_mpv, args);
}

void Player::seekTo(double seconds)
{
    if (!m_mpv)
        return;
    const QByteArray amount = QByteArray::number(seconds, 'f', 3);
    const char *args[] = { "seek", amount.constData(), "absolute", nullptr };
    mpv_command(m_mpv, args);
}

void Player::frameStep(int direction)
{
    if (!m_mpv)
        return;
    const char *args[] = { direction >= 0 ? "frame-step" : "frame-back-step", nullptr };
    mpv_command(m_mpv, args);
}

void Player::addSubtitle(const QString &url, const QString &title, const QString &lang)
{
    if (url.isEmpty() || !ensureMpv())
        return;
    const QByteArray target = url.toUtf8();
    const QByteArray name = title.toUtf8();
    const QByteArray language = lang.toUtf8();
    // "auto" adds the track without stealing the selection from whatever the
    // user, or slang, already settled on.
    const char *args[] = { "sub-add", target.constData(), "auto",
                           name.constData(), language.constData(), nullptr };
    mpv_command(m_mpv, args);
}

void Player::clearError()
{
    if (m_error.isEmpty())
        return;
    m_error.clear();
    emit errorChanged();
}

// -------------------------------------------------------------- properties ----

void Player::setPaused(bool paused)
{
    if (!m_mpv)
        return;
    int flag = paused ? 1 : 0;
    mpv_set_property(m_mpv, "pause", MPV_FORMAT_FLAG, &flag);
}

void Player::setPosition(double seconds)
{
    seekTo(seconds);
}

void Player::setVolume(double volume)
{
    if (!ensureMpv())
        return;
    double value = qBound(0.0, volume, 150.0);
    mpv_set_property(m_mpv, "volume", MPV_FORMAT_DOUBLE, &value);
}

void Player::setMuted(bool muted)
{
    if (!m_mpv)
        return;
    int flag = muted ? 1 : 0;
    mpv_set_property(m_mpv, "mute", MPV_FORMAT_FLAG, &flag);
}

void Player::setSpeed(double speed)
{
    if (!m_mpv)
        return;
    double value = qBound(0.25, speed, 4.0);
    mpv_set_property(m_mpv, "speed", MPV_FORMAT_DOUBLE, &value);
}

void Player::setAudioTrack(int id)
{
    if (!m_mpv)
        return;
    // Track id 0 means "none" to the interface; mpv spells that "no".
    if (id <= 0) {
        mpv_set_property_string(m_mpv, "aid", "no");
    } else {
        qint64 value = id;
        mpv_set_property(m_mpv, "aid", MPV_FORMAT_INT64, &value);
    }
}

void Player::setSubtitleTrack(int id)
{
    if (!m_mpv)
        return;
    if (id <= 0) {
        mpv_set_property_string(m_mpv, "sid", "no");
    } else {
        qint64 value = id;
        mpv_set_property(m_mpv, "sid", MPV_FORMAT_INT64, &value);
    }
}

void Player::setSubDelay(double seconds)
{
    if (!m_mpv)
        return;
    double value = seconds;
    mpv_set_property(m_mpv, "sub-delay", MPV_FORMAT_DOUBLE, &value);
}

QString Player::formatTime(double seconds)
{
    if (!(seconds >= 0) || seconds > 360000)
        return u"--:--"_s;
    const int total = int(seconds);
    const int h = total / 3600;
    const int m = (total % 3600) / 60;
    const int s = total % 60;
    if (h > 0)
        return QString::asprintf("%d:%02d:%02d", h, m, s);
    return QString::asprintf("%d:%02d", m, s);
}
