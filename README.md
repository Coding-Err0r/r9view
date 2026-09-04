# r9view

A touch-first image and comic viewer for Linux.

Point it at a `.cbz`, `.zip`, `.cbr` or `.7z` and it reads the images inside, in
page order, without unpacking anything first — which is the whole reason it
exists. It works just as well on an ordinary folder of pictures.

Built for a tablet and equally at home with a keyboard.

<sub>Inspired by [qimgv](https://github.com/easymodo/qimgv), rewritten around
touch input and a modern Qt Quick interface.</sub>

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Coding-Err0r/r9view/main/install.sh | bash
```

That installs the build dependencies, compiles, and puts `r9view` on your PATH
with a desktop entry, so it also appears under *Open with*. Install just for
yourself with `PREFIX=~/.local` in front of the command — then no root is needed.

Supported out of the box: Arch (and CachyOS, EndeavourOS, Manjaro), Debian and
Ubuntu, Fedora, openSUSE. On anything else the script builds fine once you have
a C++20 compiler, CMake, Qt 6 and libarchive.

## Use it

```sh
r9view ~/Downloads/chapter-01.cbz    # a comic archive
r9view ~/Pictures/holiday            # a folder of images
r9view photo.jpg                     # one image, arrow keys walk the folder
```

### Touch

| gesture | what it does |
| --- | --- |
| swipe | turn the page |
| tap the left or right edge | previous / next page |
| tap the middle | show or hide the bars |
| pinch | zoom |
| drag while zoomed | pan around the page |
| double tap | zoom to that spot, and back |

### Keyboard

| key | what it does |
| --- | --- |
| <kbd>←</kbd> <kbd>→</kbd> | previous / next page |
| <kbd>↑</kbd> <kbd>↓</kbd> | zoom in / out |
| <kbd>Space</kbd> <kbd>Backspace</kbd> | next / previous page |
| <kbd>Home</kbd> <kbd>End</kbd> | first / last page |
| <kbd>0</kbd> | reset zoom |
| <kbd>F</kbd> | cycle fit: page, width, height, actual size |
| <kbd>D</kbd> | flip reading order, for manga |
| <kbd>G</kbd> | all pages |
| <kbd>O</kbd> | open something else |
| <kbd>F11</kbd> | fullscreen |
| <kbd>Esc</kbd> | close what is open, then back to the start screen |

## What it reads

**Archives** — `zip` `cbz` `rar` `cbr` `7z` `cb7` `tar` `cbt`, via libarchive.

**Images** — everything the installed Qt plugins can decode. With the packages
the installer pulls in, that is PNG, JPEG, WebP, GIF, TIFF, BMP, SVG, JPEG 2000,
ICO, TGA, plus AVIF, HEIF/HEIC, JPEG-XL, PSD, OpenEXR, QOI, DDS, XCF and camera
RAW.

Pages come out in **natural order**, so `2.webp` sorts before `10.webp` — the
thing plain alphabetical sorting gets wrong in almost every comic archive ever
made. Non-images in the archive (the obligatory `ReadMe.txt`, macOS resource
forks) are skipped.

It remembers where you stopped in each book and reopens there, and the start
screen lists what you read recently.

## Details worth knowing

- **Archives are never unpacked.** Pages are decoded straight out of the archive
  on background threads, with the neighbours prefetched so a swipe lands on a
  drawn page. The reader keeps its position in the stream and walks forward,
  which is what makes solid `7z` and `rar` archives fast rather than quadratic.
- **Nothing is written next to your files.** Bookmarks and settings live in
  `~/.config/r9view/`.
- `r9view --list <archive>` prints the page order it would read, which is the
  quickest way to check a strangely named archive.
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

Needs Qt 6.5 or newer (Core, Gui, Qml, Quick, QuickControls2, Concurrent, Svg),
libarchive, and a C++20 compiler.

## About

Built by Rhineul Islam — <r9xcode@gmail.com>

Licensed under the GPL-3.0-or-later. See [LICENSE](LICENSE).
