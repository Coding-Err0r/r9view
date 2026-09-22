cmake_minimum_required(VERSION 3.21)
project(r9view VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Video is optional on purpose. r9view was an image and comic viewer first, and
# it still builds and runs as exactly that if libmpv is missing -- the player is
# compiled out rather than the build failing on a machine that never asked for
# it. Qt6::OpenGL is only needed for the video surface's framebuffer.
option(R9VIEW_VIDEO "Play video too, via libmpv" ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Concurrent Svg)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)

if(R9VIEW_VIDEO)
    # pkg-config is a hint, not the answer. MSYS2's mpv.pc says prefix=/ucrt64,
    # which is a path only the MSYS2 shell can resolve, so an imported target
    # built from it points at a directory CMake cannot find. Looking for the
    # header and the library directly sidesteps that -- and it is also what
    # makes a hand-dropped libmpv work: unpack one of the Windows builds from
    # github.com/zhongfly/mpv-winbuild anywhere and point CMAKE_PREFIX_PATH or
    # -DMPV_INCLUDE_DIR/-DMPV_LIBRARY at it.
    pkg_check_modules(MPV_PC QUIET mpv)
    find_path(MPV_INCLUDE_DIR
        NAMES mpv/client.h
        HINTS ${MPV_PC_INCLUDE_DIRS} ${MPV_PC_INCLUDEDIR})
    find_library(MPV_LIBRARY
        NAMES mpv libmpv libmpv-2 mpv-2
        HINTS ${MPV_PC_LIBRARY_DIRS} ${MPV_PC_LIBDIR})

    if(MPV_INCLUDE_DIR AND MPV_LIBRARY)
        find_package(Qt6 6.5 REQUIRED COMPONENTS OpenGL)
        message(STATUS "r9view: video enabled, libmpv ${MPV_PC_VERSION} (${MPV_LIBRARY})")
    else()
        set(R9VIEW_VIDEO OFF)
        message(WARNING
            "r9view: libmpv not found, building without video.\n"
            "  Install it and reconfigure to get the player:\n"
            "    Arch      pacman -S mpv\n"
            "    Debian    apt install libmpv-dev\n"
            "    Fedora    dnf install mpv-libs-devel\n"
            "    MSYS2     pacman -S mingw-w64-ucrt-x86_64-mpv")
    endif()
endif()

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(r9view
    src/main.cpp
    src/book.cpp
    src/book.h
    src/naturalsort.cpp
    src/naturalsort.h
    src/pageprovider.cpp
    src/pageprovider.h
    src/source.cpp
    src/source.h
    # Playlist only enumerates and matches -- no mpv, no decoding -- so it is
    # always built. It keeps --list useful for checking subtitle matching even
    # on a machine with no libmpv at all.
    src/playlist.cpp
    src/playlist.h
)

if(R9VIEW_VIDEO)
    target_sources(r9view PRIVATE
        src/player.cpp
        src/player.h
        src/videosurface.cpp
        src/videosurface.h
    )
endif()

# Globbed with CONFIGURE_DEPENDS so adding a QML file does not mean remembering
# to add it here as well -- forgetting only shows up at runtime, as "X is not a
# type", which is a poor way to find out.
file(GLOB R9VIEW_QML RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml)

# The player's interface refers to types that only exist when libmpv does, so
# without video those files are left out of the module entirely rather than
# failing to resolve at runtime. Book never reports a video in that case, so
# nothing ever asks for them.
if(NOT R9VIEW_VIDEO)
    list(FILTER R9VIEW_QML EXCLUDE REGEX "qml/(Video|Tracks|Speed)[A-Za-z]*\\.qml$")
endif()

file(GLOB R9VIEW_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} qml/icons/*.svg)

# The sources live in qml/ for tidiness, but the QML module expects them at its
# own root -- so every file is aliased back to its bare name (and icons to
# icons/<name>) inside the resource system.
foreach(qmlfile IN LISTS R9VIEW_QML)
    get_filename_component(alias ${qmlfile} NAME)
    set_source_files_properties(${qmlfile} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()
foreach(icon IN LISTS R9VIEW_ICONS)
    get_filename_component(alias ${icon} NAME)
    set_source_files_properties(${icon} PROPERTIES QT_RESOURCE_ALIAS icons/${alias})
endforeach()
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(r9view
    URI R9View
    VERSION 1.0
    QML_FILES ${R9VIEW_QML}
    RESOURCES ${R9VIEW_ICONS}
)

target_include_directories(r9view PRIVATE src)
target_link_libraries(r9view PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Concurrent Qt6::Svg
    PkgConfig::LIBARCHIVE
)

if(R9VIEW_VIDEO)
    target_compile_definitions(r9view PRIVATE R9VIEW_VIDEO)
    target_include_directories(r9view PRIVATE ${MPV_INCLUDE_DIR})
    target_link_libraries(r9view PRIVATE Qt6::OpenGL ${MPV_LIBRARY})
endif()

if(WIN32)
    # The manifest is not optional. Without it the process is held to MAX_PATH
    # and libmpv reports "Invalid argument" for any file more than 260
    # characters deep, which is easy to reach inside a season folder. It also
    # asks for UTF-8 as the process code page, so release names that are not
    # ASCII survive the trip to libmpv.
    enable_language(RC)
    set(CMAKE_RC_FLAGS "${CMAKE_RC_FLAGS} -I${CMAKE_CURRENT_SOURCE_DIR}/packaging")
    target_sources(r9view PRIVATE packaging/r9view.rc)

    # A release build should not flash up a console window. Debug builds keep
    # theirs, because that is where R9VIEW_DEBUG's output goes.
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        set_target_properties(r9view PROPERTIES WIN32_EXECUTABLE TRUE)
    endif()
endif()

# Desktop entries, icon themes and AppStream metadata are all freedesktop
# things; installing them on Windows would just scatter files nobody reads.
if(UNIX AND NOT APPLE)
    include(GNUInstallDirs)
    install(TARGETS r9view RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(FILES packaging/io.github.codingerr0r.r9view.desktop
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)
    install(FILES qml/icons/r9view.svg
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/scalable/apps
            RENAME io.github.codingerr0r.r9view.svg)
    install(FILES packaging/io.github.codingerr0r.r9view.metainfo.xml
            DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/metainfo)
endif()
