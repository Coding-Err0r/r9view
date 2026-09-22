#!/usr/bin/env bash
# Headless regression checks, run through --list so nothing needs a display.
#
#   tools/make-fixtures.sh /tmp/r9fix
#   tools/regression.sh ./build/r9view /tmp/r9fix
#
# Every case here is one that was actually got wrong at some point. The
# subtitle ones in particular: each came from a real layout that broke a
# plausible-looking matcher.
set -uo pipefail

EXE="${1:-./build/r9view}"
FIX="${2:-fixtures}"

pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
no() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

has()  { if printf '%s' "$3" | grep -qF "$2"; then ok "$1"; else no "$1"; fi; }
hasnt() { if printf '%s' "$3" | grep -qF "$2"; then no "$1"; else ok "$1"; fi; }

run() { "$EXE" --list "$1" 2>&1 | tr -d '\r'; }

echo "images"
o=$(run "$FIX/comic")
# 1,2,3,10,11,20 -- the ordering plain alphabetical sorting gets wrong.
has  "natural page order"            "$(printf '4\t10.png')" "$o"
hasnt "ReadMe.txt is not a page"     "ReadMe.txt"            "$o"
o=$(run "$FIX/comic.cbz")
has  "same order inside a cbz"       "$(printf '4\t./10.png')" "$o"
o=$(run "$FIX/comic/10.png")
has  "one image opens its folder"    "$(printf '1\t1.png')"  "$o"

echo "video"
o=$(run "$FIX/season")
has  "episodes found"                "Show - 01.mkv"         "$o"
hasnt "a sample clip is not episode three" "Sample.mkv"      "$o"
has  "fonts directory found"         "fonts"                 "$o"

echo "subtitles"
# Subs/<episode>/<track>_<lang>: the leading number is the TRACK, and reading
# it as an episode puts episode one's dialogue under episode two.
has  "ep01 takes Subs/01"            "Subs/01/2_eng.srt"     "$o"
has  "ep02 takes Subs/02"            "Subs/02/2_eng.srt"     "$o"
second=$(printf '%s' "$o" | awk '/^2\t/,0')
hasnt "ep02 does not also take Subs/01" "Subs/01"            "$second"

echo "archives"
o=$(run "$FIX/season-deflate.zip")
has  "video inside a zip"            "Show - 01.mkv"         "$o"
has  "subtitles addressed inside it" "archive://"            "$o"
o=$(run "$FIX/season.7z")
has  "and inside a 7z"               "Show - 01.mkv"         "$o"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
