# Video integration: what was verified on the machine, not assumed

Everything below was tested against the real toolchain before any code was
written. Where a claim is marked VERIFIED it was produced by running the command
shown; nothing here is quoted from documentation alone.

## Toolchain

MSYS2 UCRT64 (`C:/msys64/ucrt64`) is the environment that builds this project on
Windows. It supplies pkg-config and libarchive, which is why the Linux-shaped
CMakeLists already builds here unmodified.

    Qt 6.11.2      qt6-base, qt6-declarative, qt6-imageformats, qt6-svg, qt6-tools
    gcc 16.2.0     cmake 4.4.2, ninja 1.13.2
    libarchive 3.8.9
    mpv 0.41.0     libmpv client API 2.5.0   (mingw-w64-ucrt-x86_64-mpv)

libmpv ships `include/mpv/{client,render,render_gl,stream_cb}.h`,
`lib/libmpv.dll.a`, `bin/libmpv-2.dll` (~3 MB) and a working `lib/pkgconfig/mpv.pc`,
so `pkg_check_modules(MPV mpv)` matches how libarchive is already found.

## mpv reads archives natively -- VERIFIED

mpv is built against libarchive and exposes an `archive://` protocol, so r9view
does **not** need a custom `stream_cb` reader, a stored-zip offset parser, or
extraction to a temp file. The URL shape is:

    archive://<absolute-archive-path>|<entry-path-inside>

Playing a member of a deflate-compressed zip found every track:

    mpv --vo=null --ao=null --frames=3 "archive://C:/.../season-deflate.zip|Show - 01.mkv"
    -> Video --vid=1 (h264 320x240 24 fps)
       Audio --aid=1 --alang=jpn 'Japanese 2.0' [default]
       Audio --aid=2 --alang=eng 'English Dub'
       Subs  --sid=1 --slang=eng 'Signs & Songs' (ass)

### Seeking inside an archive works -- VERIFIED

This was the open question, because r9view's own ArchiveSource is forward-only.
mpv's archive stream reports itself seekable and lands on the right timestamp:

    --start=7 on archive://...|Show - 01.mkv   -> time-pos=00:00:07  seekable=yes

Confirmed for all three containers tested, including solid 7z:

    deflate zip   seekable=yes, time-pos=00:00:07
    stored zip    seekable=yes, time-pos=00:00:07
    7z            seekable=yes, time-pos=00:00:07

### Subtitles load straight out of the archive -- VERIFIED

An `archive://` URL is accepted wherever mpv takes a subtitle path, so subtitle
members do not need extracting either:

    --sub-file="archive://.../season-deflate.zip|Subs/01/2_eng.srt"
    -> Subs --sid=2 '2_eng.srt' (subrip) [external]

## mpv will NOT find nested subtitles by itself -- VERIFIED

`--sub-auto=all` only looks beside the video. With the file laid out as

    season/Show - 01.mkv
    season/Subs/01/2_eng.srt

mpv loaded only the embedded track and ignored `Subs/01/2_eng.srt` entirely.
So r9view has to do its own recursive discovery and issue explicit `sub-add`
commands. This is the feature the user asked for twice, and it cannot be
delegated to mpv.

## Consequences for the design

- No custom stream layer. A folder entry plays from its path; an archive entry
  plays from an `archive://archive|entry` URL. One code path, two URL shapes.
- Subtitle discovery is r9view's job, on disk and inside archives alike, and the
  results are attached with `sub-add`.
- The existing ArchiveSource stays exactly as it is and keeps serving comic
  pages. Archive *enumeration* is reused to find video and subtitle members;
  archive *reading* for video never goes through it.
