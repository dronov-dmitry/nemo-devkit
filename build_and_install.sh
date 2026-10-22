#!/bin/bash
set -e

# Building directly on a flaky external drive (e.g. NTFS via FUSE) can fail
# with I/O errors (EIO, getcwd/output-error), so this script builds and
# installs strictly from a local copy of the sources. The local copy is
# synced from NEMO_SRC on the first run. The script can be launched from any
# directory, including a "broken" one on an external drive.
#
# Environment variables:
#   NEMO_LOCAL_SRC       local working copy to build from (default: ~/nemo-build)
#   NEMO_SRC             source copy to sync from on the first run
#                        (default: ~/nemo-src; clone your fork there if missing)
#   NEMO_FEATURE_SYMBOL  symbol that proves the patch is installed
#                        (default: nemo_window_dnd_source_press)
#   NEMO_FORK            fork URL used in the "how to get sources" hint

LOCAL_SRC="${NEMO_LOCAL_SRC:-$HOME/nemo-build}"   # local copy of the patched branch
SRC_DIR="${NEMO_SRC:-$HOME/nemo-src}"             # source copy to sync from
BUILD_DIR="$LOCAL_SRC/builddir"
FEATURE_SYMBOL="${NEMO_FEATURE_SYMBOL:-nemo_window_dnd_source_press}"
FORK="${NEMO_FORK:-https://github.com/dronov-dmitry/nemo.git}"

echo "==> Checking and installing build dependencies..."
# Dependencies are installed as a convenience, but the build must not fail
# because of third-party repos: a broken PPA makes apt-get update return a
# non-zero exit code, and set -e used to stop the whole script before building.
if ! sudo apt-get update -qq; then
	echo "    warning: apt-get update reported an error — continuing"
fi
sudo apt-get install -y -qq \
  libgtk-3-dev libglib2.0-dev libxml2-dev libnotify-dev \
  libpango1.0-dev libcairo2-dev libgdk-pixbuf2.0-dev libatk1.0-dev \
  libdbus-glib-1-dev libx11-dev libxext-dev libxrandr-dev \
  libexif-dev libjpeg-dev libpng-dev libstartup-notification0-dev \
  libpolkit-gobject-1-dev libjson-glib-dev \
  libnemo-extension-dev ccache gettext meson ninja-build \
  gobject-introspection libgirepository1.0-dev \
  libcinnamon-desktop-dev libgail-3-dev libxapp-dev libexempi-dev \
  libgsf-1-dev libtracker-sparql-3.0-dev libselinux1-dev \
  libgtk-layer-shell-dev libwayland-dev python3-setuptools \
  || echo "    warning: could not install some packages — continuing"

# If the local copy does not exist yet — sync it from the source copy
# (only if it is readable; otherwise report honestly what to do).
if [ ! -d "$LOCAL_SRC/.git" ]; then
	if [ -d "$SRC_DIR/.git" ]; then
		echo "==> Creating local source copy: $SRC_DIR -> $LOCAL_SRC"
		mkdir -p "$LOCAL_SRC"
		rsync -a --exclude builddir "$SRC_DIR/" "$LOCAL_SRC/" \
			|| { echo "    rsync failed (source unavailable)" >&2; exit 1; }
	else
		echo "    No local copy at $LOCAL_SRC and the source copy at $SRC_DIR is unavailable." >&2
		echo "    Clone the patched branch first:" >&2
		echo "        git clone --branch <branch> $FORK $SRC_DIR" >&2
		exit 1
	fi
fi

# Configure if builddir is not created yet.
if [ ! -f "$BUILD_DIR/build.ninja" ]; then
	echo "==> Configuring meson (local)..."
	meson setup "$BUILD_DIR" "$LOCAL_SRC" --prefix=/usr
fi

echo "==> Building (local)..."
# g-ir-scanner crashes with "No module named 'distutils.msvccompiler'": ~/.local
# contains a newer setuptools where this module was removed. The system
# setuptools still has it, so disable user site-packages for the build.
PYTHONNOUSERSITE=1 ninja -C "$BUILD_DIR"

echo "==> Installing (sudo)..."
sudo env PYTHONNOUSERSITE=1 ninja -C "$BUILD_DIR" install

echo "==> Checking the installed binary..."
echo "    $(nemo --version 2>/dev/null | head -1 || echo 'nemo failed to start')"
if nm /usr/bin/nemo 2>/dev/null | grep -q "$FEATURE_SYMBOL"; then
	echo "    OK: patch installed ($FEATURE_SYMBOL found in /usr/bin/nemo)"
else
	echo "    ERROR: symbol $FEATURE_SYMBOL not found in /usr/bin/nemo" >&2
	exit 1
fi

echo "==> Done!"

printf "Restart Nemo now? [y/N]: "
read -r r || true
case "${r:-}" in
	y|Y|yes|Yes)
		echo "==> Restarting Nemo..."
		nemo -q 2>/dev/null || true
		sleep 1
		nohup nemo >/dev/null 2>&1 &
		disown || true
		echo "    Nemo restarted."
		;;
	*)
		echo "    Restart Nemo manually to test:"
		echo "        nemo -q && sleep 1 && nemo ~ &"
		;;
esac
