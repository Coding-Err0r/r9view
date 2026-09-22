#pragma once

#include <QString>
#include <QStringList>
#include <QVector>

#include <memory>

// A subtitle we went and found, rather than one mpv stumbled across.
struct SubtitleRef {
    QString url;     // a path, or archive://<archive>|<entry>
    QString title;   // what the track sheet shows
    QString lang;    // ISO code, when one could be worked out
    int rank = 0;    // how confident the match was; higher wins
};

// One playable thing.
struct MediaEntry {
    QString name;               // path as it appears in the folder or archive
    QString display;            // what the UI shows
    QString url;                // what Player::open() is handed
    qint64 size = 0;
    QVector<SubtitleRef> subtitles;
};

// A flat, ordered list of video or audio that came from somewhere: a folder, an
// archive, or a single file whose neighbours are worth having.
//
// This is the video counterpart of PageSource, and deliberately not a subclass
// of it. PageSource exists to hand raw bytes to a decoder; nothing here decodes
// anything. mpv opens the URL itself -- reading and seeking inside archives on
// its own, since it is linked against libarchive too -- so a playlist only has
// to work out what exists, in what order, and which subtitles belong to what.
//
// Scanning is recursive, which is the one place this differs sharply from
// FolderSource. A comic folder is flat and recursing would merge unrelated
// chapters, but a season folder is almost never flat: Season 1/, Specials/ and
// OVA/ are the norm, and refusing to look inside them finds nothing at all.
class Playlist
{
public:
    // Returns null when `path` holds nothing playable -- which is how Book
    // knows to fall back to opening it as images.
    static std::unique_ptr<Playlist> open(const QString &path, int *startIndex, QString *error);

    const QVector<MediaEntry> &entries() const { return m_entries; }
    int count() const { return m_entries.size(); }
    QString title() const { return m_title; }
    QString location() const { return m_location; }
    bool isArchive() const { return m_isArchive; }

    // Directories of loose fonts found beside the media, for ASS subtitles that
    // expect them. Fonts attached inside an MKV need no help; a Fonts/ folder
    // next to the episodes does.
    QStringList fontDirs() const { return m_fontDirs; }

    int indexOfName(const QString &name) const;

    // One candidate subtitle, with everything worked out that does not depend
    // on the video it will be compared against. Hoisted out of the match loop
    // because otherwise a folder of N episodes and M files runs the naming
    // regexes N*M times to learn the same M answers.
    struct Candidate {
        QString path;
        QString dir;
        QString stem;
        QString folder;          // last component of dir
        QString lang;            // ISO code, if one was found
        QString language;        // its display name
        int episode = -1;
        int folderEpisode = -1;
        bool inSubtitleFolder = false;
    };

    static QVector<Candidate> candidates(const QStringList &scope);

    // Exposed for testing and for --list: given every file in scope, work out
    // which subtitles belong to `video`, best match first.
    static QVector<SubtitleRef> matchSubtitles(const QString &video,
                                               const QStringList &scope,
                                               int videoCount,
                                               const QString &urlPrefix);
    static QVector<SubtitleRef> matchSubtitles(const QString &video,
                                               const QVector<Candidate> &scope,
                                               int videoCount,
                                               const QString &urlPrefix);

    // The episode number a release filename is trying to convey, or -1. Public
    // because getting this wrong is the difference between the right subtitles
    // and episode 12's dialogue over episode 1.
    static int episodeNumber(const QString &name);

private:
    void build(const QStringList &files, const QString &urlPrefix);

    QVector<MediaEntry> m_entries;
    QString m_title;
    QString m_location;
    bool m_isArchive = false;
    QStringList m_fontDirs;
};
