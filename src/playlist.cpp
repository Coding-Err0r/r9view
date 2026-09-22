#include "playlist.h"
#include "naturalsort.h"
#include "source.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSet>

#include <algorithm>

using namespace Qt::StringLiterals;

namespace {

// How deep a folder is walked. Season 1/Extras/Creditless/ is about as nested as
// releases get; beyond that we are indexing someone's whole drive by accident.
constexpr int kMaxDepth = 6;

QString stemOf(const QString &path)
{
    return QFileInfo(path).completeBaseName();
}

QString dirOf(const QString &path)
{
    const qsizetype slash = path.lastIndexOf(u'/');
    return slash < 0 ? QString() : path.left(slash);
}

QString lastComponent(const QString &path)
{
    const qsizetype slash = path.lastIndexOf(u'/');
    return slash < 0 ? path : path.mid(slash + 1);
}

// Does any component of this path look like a subtitle folder?
bool inSubtitleFolder(const QString &dir)
{
    static const QSet<QString> names = {
        u"subs"_s, u"sub"_s, u"subtitles"_s, u"subtitle"_s, u"subtitulos"_s,
        u"legendas"_s, u"sous-titres"_s, u"untertitel"_s,
    };
    for (const QString &part : dir.split(u'/', Qt::SkipEmptyParts)) {
        if (names.contains(part.toLower()))
            return true;
    }
    return false;
}

// Video files that are not the thing you came to watch. Releases habitually
// ship a short Sample.mkv beside the feature, and trackers drop their own
// advertisement in as a playable file. Counting these as content is not a
// cosmetic problem: "is there exactly one video here" is what decides whether a
// Subs/ folder of bare language codes can be attached, and a stray sample turns
// that one into two and loses every subtitle.
bool isSampleOrAdvert(const QString &relativePath)
{
    // Anchored at the start of a path component on purpose. A release group's
    // tag routinely looks like a domain -- "...AAC-[YTS.MX].mp4" -- and matching
    // a bare ".mx" anywhere would throw the feature away and keep the sample.
    static const QRegularExpression pattern(
        u"^(?:sample|rarbg|www\\.)|(?:^|[^a-z0-9])sample(?:[^a-z0-9]|$)"_s,
        QRegularExpression::CaseInsensitiveOption);

    for (const QString &part : relativePath.split(u'/', Qt::SkipEmptyParts)) {
        if (pattern.match(part).hasMatch())
            return true;
    }
    return false;
}

// Tokens that are release metadata rather than anything to do with which
// episode this is. Stripping them first is what stops "1080p" and "x265" from
// being read as episode numbers.
bool isNoiseToken(const QString &token)
{
    static const QRegularExpression noise(
        u"^(?:"
        u"\\d{3,4}p|[xh]\\.?26[45]|hevc|avc|av1|vp9|divx|xvid|"
        u"\\d{1,2}bits?|10bit|8bit|hi10p?|"
        u"bd|bdrip|bluray|blu-ray|brrip|dvd|dvdrip|web|webrip|web-dl|webdl|hdtv|remux|"
        u"aac|ac3|eac3|flac|dts|dtshd|truehd|opus|mp3|\\d\\.\\d|"
        u"dual|audio|multi|subs?|eng|jpn|jap|sub|subbed|dub|dubbed|"
        u"uncensored|censored|repack|proper|final|complete|batch|"
        u"19\\d\\d|20\\d\\d|"
        u"ova|oad|ona|nced|ncop|sp"
        u")$"_s,
        QRegularExpression::CaseInsensitiveOption);
    return noise.match(token).hasMatch();
}

} // namespace

// The episode number, or -1.
//
// Release naming is a swamp, so this works by elimination: try the explicit
// season/episode forms first, then strip everything that is obviously metadata
// and take the last standalone number left standing. "Show - 01 [1080p][x265]"
// gives 1; "Show S01E02" gives 2; "Mouchette.1967.1080p" gives -1, which is the
// right answer for a film.
int Playlist::episodeNumber(const QString &name)
{
    const QString stem = stemOf(lastComponent(name));

    // S01E02, 1x02, and the bare E02 that specials folders like.
    static const QRegularExpression seasonEpisode(
        u"(?:^|[^a-z0-9])(?:s(?:eason)?\\s*\\d{1,2}\\s*[ex]|\\d{1,2}x|ep?)\\s*(\\d{1,4})(?:[^0-9]|$)"_s,
        QRegularExpression::CaseInsensitiveOption);
    auto m = seasonEpisode.match(stem);
    if (m.hasMatch())
        return m.captured(1).toInt();

    // A number sitting on its own after a separator: "Show - 01", "Show_-_01_".
    static const QRegularExpression separated(
        u"(?:\\s-\\s|_-_|\\s#)\\s*(\\d{1,4})(?:[^0-9]|$)"_s);
    m = separated.match(stem);
    if (m.hasMatch())
        return m.captured(1).toInt();

    // Otherwise: break into tokens, throw away the metadata, take the last
    // number that survives.
    static const QRegularExpression splitter(u"[\\s._\\-\\[\\]()]+"_s);
    int found = -1;
    for (const QString &token : stem.split(splitter, Qt::SkipEmptyParts)) {
        if (isNoiseToken(token))
            continue;
        bool ok = false;
        const int value = token.toInt(&ok);
        if (ok && value >= 0 && value < 2000)
            found = value;
    }
    return found;
}

namespace {

// Language codes that turn up in subtitle filenames, mapped to something worth
// showing. Both the two- and three-letter forms appear in the wild, and a file
// called plainly "ENG.srt" is a whole naming convention on its own.
const QHash<QString, QString> &languageNames()
{
    static const QHash<QString, QString> map = {
        { u"en"_s, u"English"_s },   { u"eng"_s, u"English"_s },
        { u"ja"_s, u"Japanese"_s },  { u"jpn"_s, u"Japanese"_s }, { u"jap"_s, u"Japanese"_s },
        { u"es"_s, u"Spanish"_s },   { u"spa"_s, u"Spanish"_s },  { u"esp"_s, u"Spanish"_s },
        { u"fr"_s, u"French"_s },    { u"fre"_s, u"French"_s },   { u"fra"_s, u"French"_s },
        { u"de"_s, u"German"_s },    { u"ger"_s, u"German"_s },   { u"deu"_s, u"German"_s },
        { u"it"_s, u"Italian"_s },   { u"ita"_s, u"Italian"_s },
        { u"pt"_s, u"Portuguese"_s },{ u"por"_s, u"Portuguese"_s },
        { u"ru"_s, u"Russian"_s },   { u"rus"_s, u"Russian"_s },
        { u"zh"_s, u"Chinese"_s },   { u"chi"_s, u"Chinese"_s },  { u"zho"_s, u"Chinese"_s },
        { u"ko"_s, u"Korean"_s },    { u"kor"_s, u"Korean"_s },
        { u"ar"_s, u"Arabic"_s },    { u"ara"_s, u"Arabic"_s },
        { u"nl"_s, u"Dutch"_s },     { u"dut"_s, u"Dutch"_s },    { u"nld"_s, u"Dutch"_s },
        { u"pl"_s, u"Polish"_s },    { u"pol"_s, u"Polish"_s },
        { u"sv"_s, u"Swedish"_s },   { u"swe"_s, u"Swedish"_s },
        { u"da"_s, u"Danish"_s },    { u"dan"_s, u"Danish"_s },
        { u"fi"_s, u"Finnish"_s },   { u"fin"_s, u"Finnish"_s },
        { u"no"_s, u"Norwegian"_s }, { u"nor"_s, u"Norwegian"_s },
        { u"el"_s, u"Greek"_s },     { u"gre"_s, u"Greek"_s },    { u"ell"_s, u"Greek"_s },
        { u"tr"_s, u"Turkish"_s },   { u"tur"_s, u"Turkish"_s },
        { u"cs"_s, u"Czech"_s },     { u"cze"_s, u"Czech"_s },
        { u"hu"_s, u"Hungarian"_s }, { u"hun"_s, u"Hungarian"_s },
        { u"ro"_s, u"Romanian"_s },  { u"rum"_s, u"Romanian"_s },
        { u"he"_s, u"Hebrew"_s },    { u"heb"_s, u"Hebrew"_s },
        { u"hi"_s, u"Hindi"_s },     { u"hin"_s, u"Hindi"_s },
        { u"th"_s, u"Thai"_s },      { u"tha"_s, u"Thai"_s },
        { u"vi"_s, u"Vietnamese"_s },{ u"vie"_s, u"Vietnamese"_s },
        { u"id"_s, u"Indonesian"_s },{ u"ind"_s, u"Indonesian"_s },
        { u"bn"_s, u"Bengali"_s },   { u"ben"_s, u"Bengali"_s },
        { u"uk"_s, u"Ukrainian"_s }, { u"ukr"_s, u"Ukrainian"_s },
    };
    return map;
}

// Pull a language out of a subtitle path. Handles the two conventions that
// matter: a tag somewhere in the filename ("...eng.srt", "01.en.forced.ass"),
// and the whole stem being nothing but a code ("Subs/ENG.srt"). A parent
// directory named after a language counts too ("Subs/English/01.srt").
QString languageOf(const QString &relativePath, QString *display)
{
    const QString stem = stemOf(lastComponent(relativePath));
    const auto &names = languageNames();

    // Spelled-out languages appear as directory names ("Subs/English/01.srt")
    // and occasionally in filenames, so the map is needed in both directions.
    static const QHash<QString, QString> byName = [] {
        QHash<QString, QString> reverse;
        for (auto it = languageNames().cbegin(); it != languageNames().cend(); ++it)
            reverse.insert(it.value().toLower(), it.key());
        return reverse;
    }();

    const auto codeFor = [&](const QString &token) -> QString {
        const QString lower = token.toLower();
        if (lower.size() <= 3 && names.contains(lower))
            return lower;
        return byName.value(lower);
    };

    static const QRegularExpression splitter(u"[\\s._\\-\\[\\]()]+"_s);
    const QStringList tokens = stem.split(splitter, Qt::SkipEmptyParts);

    // Later tokens win: in "01.eng.forced" the leading part is the episode.
    QString code;
    for (const QString &token : tokens) {
        const QString hit = codeFor(token);
        if (!hit.isEmpty())
            code = hit;
    }

    // Failing that, a directory named for a language.
    if (code.isEmpty()) {
        for (const QString &part : dirOf(relativePath).split(u'/', Qt::SkipEmptyParts)) {
            const QString hit = codeFor(part);
            if (!hit.isEmpty())
                code = hit;
        }
    }

    if (display && !code.isEmpty())
        *display = names.value(code);
    return code;
}

} // namespace

// --------------------------------------------------------------- matching ----

// Everything about one candidate subtitle that does not depend on which video
// it is being compared against. Working it out once per file instead of once
// per (video, file) pair is what keeps a thirteen-episode folder from running
// the episode-number regex a few hundred times over.
QVector<Playlist::Candidate> Playlist::candidates(const QStringList &scope)
{
    // A VobSub pair is one subtitle, addressed by its .idx. Loading the .sub
    // beside it would add a second, broken track.
    QSet<QString> idxStems;
    for (const QString &file : scope) {
        if (QFileInfo(file).suffix().compare(u"idx"_s, Qt::CaseInsensitive) == 0)
            idxStems.insert(dirOf(file) + u'/' + stemOf(lastComponent(file)));
    }

    QVector<Playlist::Candidate> out;
    for (const QString &file : scope) {
        if (!PageSource::isSubtitleFile(file))
            continue;
        const QString dir = dirOf(file);
        const QString stem = stemOf(lastComponent(file));
        if (QFileInfo(file).suffix().compare(u"sub"_s, Qt::CaseInsensitive) == 0
            && idxStems.contains(dir + u'/' + stem))
            continue;

        Playlist::Candidate c;
        c.path = file;
        c.dir = dir;
        c.stem = stem;
        c.folder = lastComponent(dir);
        c.episode = episodeNumber(file);
        c.folderEpisode = episodeNumber(c.folder);
        c.inSubtitleFolder = inSubtitleFolder(dir);
        c.lang = languageOf(file, &c.language);
        out.append(c);
    }
    return out;
}

QVector<SubtitleRef> Playlist::matchSubtitles(const QString &video,
                                              const QStringList &scope,
                                              int videoCount,
                                              const QString &urlPrefix)
{
    return matchSubtitles(video, candidates(scope), videoCount, urlPrefix);
}

QVector<SubtitleRef> Playlist::matchSubtitles(const QString &video,
                                              const QVector<Candidate> &scope,
                                              int videoCount,
                                              const QString &urlPrefix)
{
    const QString videoDir = dirOf(video);
    const QString videoStem = stemOf(lastComponent(video));
    const int videoEpisode = episodeNumber(video);

    QVector<SubtitleRef> found;
    for (const Candidate &candidate : scope) {
        const QString &file = candidate.path;
        const QString &dir = candidate.dir;
        const QString &stem = candidate.stem;
        const int episode = candidate.episode;

        int rank = 0;
        if (dir == videoDir && stem.compare(videoStem, Qt::CaseInsensitive) == 0) {
            rank = 100;                                  // 01.mkv + 01.srt
        } else if (dir == videoDir && stem.startsWith(videoStem, Qt::CaseInsensitive)) {
            rank = 90;                                   // 01.mkv + 01.eng.srt
        } else if (candidate.inSubtitleFolder) {
            const QString &folder = candidate.folder;
            const int folderEpisode = candidate.folderEpisode;
            if (stem.compare(videoStem, Qt::CaseInsensitive) == 0) {
                rank = 85;                               // Subs/01.ass
            } else if (stem.startsWith(videoStem, Qt::CaseInsensitive)) {
                rank = 80;                               // Subs/01.eng.ass
            } else if (folder.compare(videoStem, Qt::CaseInsensitive) == 0) {
                rank = 78;                               // Subs/<episode name>/...
            } else if (folderEpisode >= 0 && videoEpisode >= 0) {
                // The folder says which episode these belong to, and that is
                // the end of it. Inside Subs/01/ a file called 2_eng.ass is
                // track 2 of episode 1 -- reading the 2 as an episode number is
                // how episode 1's subtitles end up under episode 2.
                rank = folderEpisode == videoEpisode ? 72 : 0;
            } else if (videoEpisode >= 0 && episode == videoEpisode) {
                rank = 70;                               // Subs/01.eng.srt
            } else if (videoCount == 1) {
                rank = 60;                               // Subs/ENG.srt, one film
            }
        } else if (videoEpisode >= 0 && episode == videoEpisode
                   && dir.startsWith(videoDir)) {
            rank = 40;
        } else if (videoCount == 1 && dir.startsWith(videoDir)) {
            rank = 30;                                   // lone film, sub anywhere
        }

        if (rank <= 0)
            continue;

        SubtitleRef ref;
        ref.url = urlPrefix.isEmpty() ? file : urlPrefix + file;
        ref.rank = rank;
        const QString &display = candidate.language;
        ref.lang = candidate.lang;
        // The filename carries information the language alone does not -- two
        // English subs from different DVD masters, forced-only tracks -- so the
        // title keeps it, and only falls back to the language.
        if (stem.compare(videoStem, Qt::CaseInsensitive) == 0)
            ref.title = display.isEmpty() ? u"External"_s : display;
        else
            ref.title = display.isEmpty() ? stem : (stem.size() <= 3 ? display : stem);
        if (stem.contains(u"forced"_s, Qt::CaseInsensitive) && !ref.title.contains(u"forced"_s, Qt::CaseInsensitive))
            ref.title += u" (forced)"_s;
        found.append(ref);
    }

    std::sort(found.begin(), found.end(), [](const SubtitleRef &a, const SubtitleRef &b) {
        if (a.rank != b.rank)
            return a.rank > b.rank;
        return naturalLess(a.title, b.title);
    });
    return found;
}

// ----------------------------------------------------------------- opening ----

void Playlist::build(const QStringList &files, const QString &urlPrefix)
{
    QStringList playable;
    QStringList samples;
    for (const QString &file : files) {
        if (!PageSource::isPlayableFile(file))
            continue;
        if (isSampleOrAdvert(file))
            samples.append(file);
        else
            playable.append(file);
    }
    // Unless that is all there was -- someone who opens a folder holding
    // nothing but a sample clip still meant to watch it.
    if (playable.isEmpty())
        playable = samples;
    std::sort(playable.begin(), playable.end(), naturalLess);

    // Loose fonts for ASS rendering. Only meaningful on disk: mpv's
    // sub-fonts-dir wants a real directory, not a path inside an archive.
    QSet<QString> fonts;
    if (!m_isArchive) {
        for (const QString &file : files) {
            const QString suffix = QFileInfo(file).suffix().toLower();
            if (suffix == u"ttf"_s || suffix == u"otf"_s || suffix == u"ttc"_s) {
                const QString dir = dirOf(file);
                fonts.insert(dir.isEmpty() ? m_location : m_location + u'/' + dir);
            }
        }
    }
    m_fontDirs = QStringList(fonts.begin(), fonts.end());
    m_fontDirs.sort();

    // The "one video here, so any subtitle in Subs/ belongs to it" rule has to
    // count videos, not entries. An album track sitting in the folder would
    // otherwise make it two and quietly switch the rule off.
    int videos = 0;
    for (const QString &file : playable) {
        if (PageSource::isVideoFile(file))
            ++videos;
    }
    if (videos == 0)
        videos = playable.size();

    const QVector<Candidate> subs = candidates(files);
    for (const QString &file : playable) {
        MediaEntry entry;
        entry.name = file;
        entry.display = lastComponent(file);
        entry.url = urlPrefix.isEmpty() ? file : urlPrefix + file;
        entry.subtitles = matchSubtitles(file, subs, videos, urlPrefix);
        m_entries.append(entry);
    }
}

int Playlist::indexOfName(const QString &name) const
{
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries.at(i).name == name)
            return i;
    }
    return -1;
}

std::unique_ptr<Playlist> Playlist::open(const QString &path, int *startIndex, QString *error)
{
    if (startIndex)
        *startIndex = 0;

    const QFileInfo info(path);
    if (!info.exists()) {
        if (error)
            *error = u"no such file or folder"_s;
        return nullptr;
    }

    // ---- an archive ----
    if (info.isFile() && PageSource::isArchiveFile(info.fileName())) {
        QString listError;
        const QStringList members = PageSource::archiveEntryNames(info.absoluteFilePath(), &listError);
        bool anyPlayable = false;
        for (const QString &member : members) {
            if (PageSource::isPlayableFile(member)) {
                anyPlayable = true;
                break;
            }
        }
        if (!anyPlayable)
            return nullptr; // a comic, almost certainly -- let PageSource have it

        auto list = std::make_unique<Playlist>();
        list->m_isArchive = true;
        list->m_title = info.completeBaseName();
        list->m_location = info.absoluteFilePath();
        // mpv reads and seeks archive members itself; nothing is unpacked.
        list->build(members, u"archive://"_s + info.absoluteFilePath() + u'|');
        return list->count() > 0 ? std::move(list) : nullptr;
    }

    // ---- a folder, or one file whose folder comes along ----
    const bool single = info.isFile();
    if (single && !PageSource::isPlayableFile(info.fileName()))
        return nullptr; // not ours

    const QDir root(single ? info.absolutePath() : info.absoluteFilePath());
    if (!root.exists()) {
        if (error)
            *error = u"no such folder"_s;
        return nullptr;
    }

    // A comic folder should not pay for a recursive walk it has no use for, and
    // Book asks the playlist first on every single open. So: look at the top
    // level only, and if it holds pictures and nothing playable, say so at once
    // and let the reader have it. A season folder either has episodes at the
    // top (walk on, the subtitles may be nested) or nothing at all at the top,
    // which is exactly the Season 1/ case worth recursing for.
    if (!single) {
        bool shallowPlayable = false;
        bool shallowImages = false;
        for (const QFileInfo &fi : root.entryInfoList(QDir::Files | QDir::Readable, QDir::NoSort)) {
            if (PageSource::isPlayableFile(fi.fileName()))
                shallowPlayable = true;
            else if (PageSource::isImageFile(fi.fileName()))
                shallowImages = true;
        }
        if (!shallowPlayable && shallowImages)
            return nullptr;
    }

    QStringList files;
    QDirIterator it(root.absolutePath(),
                    QDir::Files | QDir::Readable | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);
    const int rootDepth = root.absolutePath().count(u'/');
    while (it.hasNext()) {
        const QString absolute = it.next();
        if (absolute.count(u'/') - rootDepth > kMaxDepth)
            continue;
        const QString name = lastComponent(absolute);
        if (name.startsWith(u'.'))
            continue;
        files.append(root.relativeFilePath(absolute));
    }

    bool anyPlayable = false;
    for (const QString &file : files) {
        if (PageSource::isPlayableFile(file)) {
            anyPlayable = true;
            break;
        }
    }
    if (!anyPlayable)
        return nullptr; // a folder of pictures; PageSource's business

    auto list = std::make_unique<Playlist>();
    list->m_title = root.dirName().isEmpty() ? root.absolutePath() : root.dirName();
    list->m_location = root.absolutePath();
    // Absolute paths so mpv does not depend on the process's directory.
    list->build(files, root.absolutePath() + u'/');
    if (list->count() == 0)
        return nullptr;

    if (single && startIndex) {
        const int at = list->indexOfName(root.relativeFilePath(info.absoluteFilePath()));
        *startIndex = qMax(0, at);
    }
    return list;
}
