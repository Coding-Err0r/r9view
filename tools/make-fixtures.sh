#!/usr/bin/env bash
# Builds the sample media r9view is tested against, so a regression run does not
# depend on anyone's private library.
#
# The layouts here are copied from real releases, not invented: a dual-audio MKV
# with an embedded ASS track, subtitles buried in Subs/<episode>/, a Fonts/
# directory for ASS rendering, a sample clip that must not be mistaken for the
# feature, and a comic numbered 1,2,3,10,11,20 to catch alphabetical sorting.
#
#   tools/make-fixtures.sh [output-dir]      (default: ./fixtures)
#
# Needs ffmpeg and bsdtar. On Windows run it from an MSYS2 UCRT64 shell.
set -euo pipefail

OUT="${1:-fixtures}"
rm -rf "$OUT"
mkdir -p "$OUT/season/Subs/01" "$OUT/season/Subs/02" "$OUT/season/Fonts" "$OUT/comic"

# Resolve OUT to an absolute path up front. Joining it onto $PWD later only
# works while it is relative, and silently produces nonsense the moment someone
# passes /tmp/fixtures.
OUT="$(cd "$OUT" && pwd)"

# ffmpeg on Windows needs a native path, and the MSYS2 shell hands it a POSIX one.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
NOUT="$(native "$OUT")"

srt() {
    printf '1\n00:00:01,000 --> 00:00:04,000\n%s \xe2\x80\x94 line one\n\n2\n00:00:05,000 --> 00:00:09,000\n%s \xe2\x80\x94 line two\n' "$1" "$1" > "$2"
}

srt "Embedded" "$OUT/embedded.srt"

# Two episodes, each with two audio tracks and an embedded subtitle track, which
# is what a dual-audio release actually looks like.
for n in 01 02; do
    ffmpeg -y -v error \
        -f lavfi -i "testsrc=size=320x240:rate=24:duration=10" \
        -f lavfi -i "sine=frequency=440:duration=10" \
        -f lavfi -i "sine=frequency=880:duration=10" \
        -i "$(native "$OUT/embedded.srt")" \
        -map 0:v -map 1:a -map 2:a -map 3:s \
        -c:v libx264 -preset ultrafast -c:a aac -c:s ass \
        -metadata:s:a:0 language=jpn -metadata:s:a:0 title="Japanese 2.0" \
        -metadata:s:a:1 language=eng -metadata:s:a:1 title="English Dub" \
        -metadata:s:s:0 language=eng -metadata:s:s:0 title="Signs & Songs" \
        "$NOUT/season/Show - $n.mkv"
done
rm -f "$OUT/embedded.srt"

# The layout the whole subtitle matcher exists for: per-episode folders, with a
# leading number that is a TRACK number, not an episode number.
srt "Ep01 English" "$OUT/season/Subs/01/2_eng.srt"
srt "Ep01 Spanish" "$OUT/season/Subs/01/3_spa.srt"
srt "Ep02 English" "$OUT/season/Subs/02/2_eng.srt"

# A sample clip, which must not become episode three.
ffmpeg -y -v error -f lavfi -i "testsrc=size=160x120:rate=24:duration=2" \
    -c:v libx264 -preset ultrafast "$NOUT/season/Sample.mkv"

# A font for ASS, borrowed from the system if there is one to borrow.
for f in /c/Windows/Fonts/arial.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf; do
    [ -f "$f" ] && cp "$f" "$OUT/season/Fonts/" && break
done

# A comic whose numbering breaks alphabetical sorting, plus the obligatory decoy.
for n in 1 2 3 10 11 20; do
    ffmpeg -y -v error -f lavfi -i "testsrc=size=80x120:rate=1:duration=1" \
        -frames:v 1 -update 1 "$NOUT/comic/$n.png"
done
echo 'not a page' > "$OUT/comic/ReadMe.txt"

# Archives. Both a compressed and a stored zip, because they exercise different
# paths in mpv's archive reader, plus a 7z, which is solid.
( cd "$OUT" && bsdtar -a -cf season-deflate.zip -C season . )
( cd "$OUT" && bsdtar -a -cf season-stored.zip --options='zip:compression=store' -C season . )
( cd "$OUT" && bsdtar -a -cf season.7z -C season . )
( cd "$OUT" && bsdtar -a -cf comic.cbz --format=zip -C comic . )

echo "fixtures in $OUT:"
find "$OUT" -maxdepth 1 -mindepth 1 | sort | sed 's|^|  |'
