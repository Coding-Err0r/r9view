#!/usr/bin/env bash
# r9view installer.
#
#   curl -fsSL https://raw.githubusercontent.com/Coding-Err0r/r9view/main/install.sh | bash
#
# Installs build dependencies, compiles r9view, and puts it on your PATH with a
# desktop entry so it shows up in the launcher and in "Open with".
#
#   PREFIX=~/.local  ...   install for just you, no root needed
#   PREFIX=/usr/local ...  system-wide (default; uses sudo for the install step)
#   SKIP_DEPS=1      ...   do not touch the package manager; you manage the
#                          dependencies yourself (also what CI wants)
set -euo pipefail

REPO_URL="https://github.com/Coding-Err0r/r9view.git"
PREFIX="${PREFIX:-/usr/local}"
BRANCH="${BRANCH:-main}"

# Where a temporary clone goes, if we make one. Global rather than a local in
# main(), because the EXIT trap runs after main()'s locals are gone -- and under
# `set -u` a trap referring to a vanished local kills the script with a confusing
# "unbound variable" instead of cleaning up.
WORKDIR=""
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] && die "run this as your normal user; it calls sudo only where it needs to"

# sudo is only needed when installing outside your home directory.
SUDO=""
case "$PREFIX" in
    "$HOME"/*) ;;
    *) command -v sudo >/dev/null || die "installing to $PREFIX needs sudo; or re-run with PREFIX=~/.local"
       SUDO="sudo" ;;
esac

# ---------------------------------------------------------------- packages ---
install_deps() {
    if [ -n "${SKIP_DEPS:-}" ]; then
        info "SKIP_DEPS set -- leaving the package manager alone"
        return 0
    fi
    if ! sudo -v 2>/dev/null; then
        die "cannot get root to install dependencies.
       Run the installer from a terminal where sudo can ask for your password,
       or install the dependencies yourself and re-run with SKIP_DEPS=1."
    fi

    local id=""
    [ -r /etc/os-release ] && id=$(. /etc/os-release && echo "${ID_LIKE:-$ID}")

    case " $id " in
        *arch*)
            info "installing dependencies with pacman"
            sudo pacman -S --needed --noconfirm \
                base-devel cmake ninja git \
                qt6-base qt6-declarative qt6-svg qt6-imageformats \
                libarchive kimageformats libavif libheif libjxl
            ;;
        *debian*|*ubuntu*)
            info "installing dependencies with apt"
            sudo apt-get update
            sudo apt-get install -y \
                build-essential cmake ninja-build git pkg-config \
                qt6-base-dev qt6-declarative-dev libqt6svg6-dev \
                qml6-module-qtquick qml6-module-qtquick-controls \
                qml6-module-qtquick-layouts qml6-module-qtquick-dialogs \
                qml6-module-qtcore qml6-module-qtqml-workerscript \
                libarchive-dev qt6-image-formats-plugins kimageformat-plugins
            ;;
        *fedora*|*rhel*)
            info "installing dependencies with dnf"
            sudo dnf install -y \
                gcc-c++ cmake ninja-build git pkgconf-pkg-config \
                qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel \
                qt6-qtimageformats libarchive-devel kf6-kimageformats
            ;;
        *suse*)
            info "installing dependencies with zypper"
            sudo zypper install -y \
                gcc-c++ cmake ninja git pkg-config \
                qt6-base-devel qt6-declarative-devel qt6-svg-devel \
                qt6-imageformats libarchive-devel kimageformats
            ;;
        *)
            warn "unrecognised distribution -- skipping dependency install."
            warn "you need: a C++20 compiler, cmake, ninja, Qt 6 (base, declarative, svg,"
            warn "imageformats), libarchive, and ideally kimageformats for avif/heif/jxl."
            ;;
    esac
}

# ------------------------------------------------------------------ build ----
main() {
    for tool in git cmake; do
        command -v "$tool" >/dev/null || { install_deps; break; }
    done
    command -v git >/dev/null || die "git is still missing; install it and re-run"
    command -v cmake >/dev/null || { install_deps; }
    command -v cmake >/dev/null || die "cmake is still missing; install it and re-run"

    local src
    if [ -f "$(dirname "$0")/CMakeLists.txt" ] && grep -q 'project(r9view' "$(dirname "$0")/CMakeLists.txt" 2>/dev/null; then
        # Running from a checkout: build what is here.
        src=$(cd "$(dirname "$0")" && pwd)
        info "building from $src"
    else
        install_deps
        WORKDIR=$(mktemp -d)
        info "fetching r9view"
        git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$WORKDIR/r9view" >/dev/null 2>&1 \
            || die "could not clone $REPO_URL"
        src="$WORKDIR/r9view"
    fi

    info "compiling (this takes a minute)"
    cmake -S "$src" -B "$src/build" -G "$(command -v ninja >/dev/null && echo Ninja || echo 'Unix Makefiles')" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
    cmake --build "$src/build" --parallel

    info "installing to $PREFIX"
    $SUDO cmake --install "$src/build" >/dev/null

    # Make the launcher and "Open with" notice the new application.
    local share="$PREFIX/share"
    command -v update-desktop-database >/dev/null && $SUDO update-desktop-database "$share/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache   >/dev/null && $SUDO gtk-update-icon-cache -qtf "$share/icons/hicolor" 2>/dev/null || true

    echo
    bold "r9view is installed."
    echo "  r9view ~/Downloads/some-comic.cbz     open an archive"
    echo "  r9view ~/Pictures                     open a folder"
    echo "  r9view photo.jpg                      open one image (and its folder)"
    echo
    case ":$PATH:" in
        *":$PREFIX/bin:"*) ;;
        *) warn "$PREFIX/bin is not on your PATH -- add it to use the 'r9view' command." ;;
    esac
}

main "$@"
