# r9view

A touch-first viewer for images, comics and video.

Point it at a `.cbz`, `.zip`, `.cbr` or `.7z` and it reads the images inside, in
page order, without unpacking anything first — which is the whole reason it
exists. Point it at a season folder and it plays the episodes, finds the
subtitles, and hands you a set of touch controls mpv has never had.

Built for a tablet and equally at home with a keyboard.

<sub>Inspired by [qimgv](https://github.com/easymodo/qimgv), rewritten around
touch input and a modern Qt Quick interface. Video is [mpv](https://mpv.io)
underneath, driven through libmpv.</sub>

## Install

### Windows

Download `r9view-*-windows-x64-setup.exe` from
[Releases](https://github.com/Coding-Err0r/r9view/releases) and run it. It
installs for you alone, so it never asks for administrator rights, and it
appears under *Open with* for everything it can read.

Or from PowerShell:

```powershell
irm https://raw.githubusercontent.com/Coding-Err0r/r9view/main/install.ps1 | iex
```

There is also a portable `.zip` — unpack it anywhere and run `r9view.exe`.
Nothing else is needed; mpv and Qt are inside.

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/Coding-Err0r/r9view/main/install.sh | bash
```

That installs the build dependencies, compiles, and puts `r9view` on your PATH
with a desktop entry, so it also appears under *Open with*. Install just for
yourself with `PREFIX=~/.local` in front of the command — then no root is needed.

Supported out of the box: Arch (and CachyOS, EndeavourOS, Manjaro), Debian and
Ubuntu, Fedora, openSUSE. On anything else the script builds fine once you have
a C++20 compiler, CMake, Qt 6, libarchive and libmpv.

## Use it

```sh
r9view ~/Downloads/chapter-01.cbz    # a comic archive
r9view ~/Pictures/holiday            # a folder of images
r9view photo.jpg                     # one image, arrow keys walk the folder
r9view ~/Anime/"Some Show S01"       # a season, subtitles and all
r9view episode.mkv                   # one episode, arrows walk the folder
r9view season.zip                    # video straight out of the archive
```

What it finds decides what it becomes. A folder of pictures opens the reader; a
folder with anything playable in it opens the player. Either way `←` and `→`
move through it, and the same scrub bar sits at the bottom.

### Touch

| gesture | reading | watching |
| --- | --- | --- |
| tap the middle | show or hide the bars | show or hide the bars |
| tap the left or right edge | previous / next page | — |
| **double tap the left or right third** | zoom to that spot | **back / forward 10 seconds** |
| double tap again | — | 20 seconds, then 30, and on |
| double tap the middle | zoom to that spot | play / pause |
| press and hold | — | 2× speed until you let go |
| drag up or down, right half | — | volume |
| drag up or down, left half | — | brightness |
| swipe | turn the page | — |
| pinch | zoom | zoom |
| drag while zoomed | pan around the page | — |

### Keyboard

The same key does the reader's thing with a comic open and mpv's thing with a
video open, so neither half has to be relearned.

| key | reading | watching |
| --- | --- | --- |
| <kbd>←</kbd> <kbd>→</kbd> | previous / next page | seek 5 seconds |
| <kbd>Shift</kbd>+<kbd>←</kbd> <kbd>→</kbd> | — | seek a minute |
| <kbd>↑</kbd> <kbd>↓</kbd> | zoom in / out | volume |
| <kbd>Space</kbd> | next page | play / pause |
| <kbd>PgUp</kbd> <kbd>PgDn</kbd> | previous / next page | previous / next episode |
| <kbd>Home</kbd> <kbd>End</kbd> | first / last page | start / last episode |
| <kbd>0</kbd> | reset zoom | volume up (as in mpv) |
| <kbd>Ctrl</kbd>+<kbd>0</kbd> | reset zoom | reset zoom |
| <kbd>F</kbd> | cycle fit | fullscreen (as in mpv) |
| <kbd>M</kbd> | — | mute |
| <kbd>V</kbd> | — | subtitles on / off |
| <kbd>J</kbd> | — | next subtitle track |
| <kbd>#</kbd> | — | next audio track |
| <kbd>[</kbd> <kbd>]</kbd> | — | slower / faster |
| <kbd>{</kbd> <kbd>}</kbd> | — | half / double speed |
| <kbd>,</kbd> <kbd>.</kbd> | — | frame back / forward |
| <kbd>Backspace</kbd> | previous page | reset speed |
| <kbd>S</kbd> | — | screenshot |
| <kbd>D</kbd> | flip reading order, for manga | — |
| <kbd>G</kbd> | all pages | — |
| <kbd>O</kbd> | open something else | open something else |
| <kbd>F11</kbd> | fullscreen | fullscreen |
| <kbd>Esc</kbd> | close what is open, then back to the start screen | |

## Subtitles

Subtitles beside the video are found the way any player finds them. The ones
that are not beside it are the point: r9view looks through the whole folder, and
through the whole archive, and works out which file belongs to which episode.

All of these are found, because all of them are real layouts:

```
Show - 01.mkv  +  Show - 01.srt              the easy one
Show - 01.mkv  +  Show - 01.eng.forced.srt   language and flags from the name
Subs/01/2_eng.ass                            per-episode folder, track number
Subs/Episode 01/English.srt
Subs/ENG.srt  Subs/GRE.srt  Subs/ITA.srt     one film, subtitles named by language
Subs/srt (New Yorker, NTSC DVD).eng.srt      two English subs, told apart by title
```

Inside `Subs/01/`, a file called `2_eng.ass` is track two of episode one, not
episode two — which is the kind of thing that puts the wrong dialogue on screen
if you get it wrong. When a folder names the episode, that wins.

A `Fonts/` folder next to the episodes is handed to mpv for ASS rendering, and
fonts attached inside an MKV work on their own. Subtitles inside an archive are
loaded straight out of it; nothing is unpacked.

Everything found is offered in the track sheet with its language, its title and
where it came from, next to whatever the file already had embedded.

## What it reads

**Archives** — `zip` `cbz` `rar` `cbr` `7z` `cb7` `tar` `cbt`, via libarchive.
Video inside an archive plays and seeks without being unpacked, because mpv is
linked against libarchive as well.

**Images** — everything the installed Qt plugins can decode: PNG, JPEG, WebP,
GIF, TIFF, BMP, SVG, JPEG 2000, ICO, TGA, plus AVIF, HEIF/HEIC, JPEG-XL, PSD,
OpenEXR, QOI, DDS, XCF and camera RAW.

**Video and audio** — whatever mpv can demux, which is effectively everything:
MKV, MP4, AVI, MOV, WebM, TS, M2TS, WMV, FLV, MPEG, VOB, OGV, RM, 3GP and the
rest, plus MP3, FLAC, Opus, AAC, ALAC, WavPack, DTS and friends.

Pages come out in **natural order**, so `2.webp` sorts before `10.webp` — the
thing plain alphabetical sorting gets wrong in almost every comic archive ever
made. Non-images in the archive (the obligatory `ReadMe.txt`, macOS resource
forks) are skipped, and so is the `Sample.mkv` that ships beside so many films.

It remembers where you stopped — the page in a book, the timestamp in an episode
— and reopens there. The start screen lists what you read last.

## Details worth knowing

- **Archives are never unpacked.** Pages are decoded straight out of the archive
  on background threads, with the neighbours prefetched so a swipe lands on a
  drawn page. The reader keeps its position in the stream and walks forward,
  which is what makes solid `7z` and `rar` archives fast rather than quadratic.
- **Season folders are searched properly.** A comic folder is flat, so the image
  reader does not recurse. A season folder almost never is — the episodes live
  in `Season 1/` and the extras in `Specials/` — so the player does.
- **The picture is a scene graph item.** mpv renders into a framebuffer Qt
  composites, rather than into a window of its own stacked on top, which is what
  lets the controls be drawn over the video at all.
- **Nothing is written next to your files.** Bookmarks and settings live in
  `~/.config/r9view/` on Linux and under `HKCU\Software\r9view` on Windows.
- `r9view --list <thing>` prints what it would open, and for video it prints the
  subtitles it matched and why — the quickest way to check a strangely named
  release.
- `R9VIEW_DEBUG=1 r9view …` forces Qt's log messages to stderr. Some desktop
  sessions swallow them, which makes a QML warning impossible to see otherwise.

## Build it yourself

```sh
git clone https://github.com/Coding-Err0r/r9view.git
cd r9view
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/r9view ~/Downloads/chapter-01.cbz
```

Needs Qt 6.5 or newer (Core, Gui, Qml, Quick, QuickControls2, Concurrent, Svg,
and OpenGL for video), libarchive, libmpv, and a C++20 compiler. Without libmpv
it still builds and runs as the image and comic viewer it started as; configure
with `-DR9VIEW_VIDEO=OFF` to leave video out deliberately.

On Windows, build in an **MSYS2 UCRT64** environment:

```sh
pacman -S mingw-w64-ucrt-x86_64-{gcc,cmake,ninja,pkg-config} \
          mingw-w64-ucrt-x86_64-qt6-{base,declarative,svg,imageformats,tools} \
          mingw-w64-ucrt-x86_64-{libarchive,mpv}
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

`tools/package-windows.ps1` turns that into the distributable folder, zip and
installer.

## About

Built by Rhineul Islam — <r9xcode@gmail.com>

Licensed under the GPL-3.0-or-later. See [LICENSE](LICENSE).
