#!/bin/bash
set -e

# Building directly on a flaky external drive (e.g. NTFS via FUSE) can fail
# with I/O errors (EIO, getcwd/output-error), so this script builds and
# installs strictly from a local copy of the sources. The local copy is
# created from NEMO_SRC on the first run and re-synced with it on every run,
# so the build always contains the latest Nemo version together with the
# locally built functionality merged by nemo-update.sh. Uncommitted changes
# in the local copy are stashed and restored — never lost. The script can be
# launched from any directory, including a "broken" one on an external drive.
#
# Environment variables:
#   NEMO_LOCAL_SRC       local working copy to build from (default: ~/nemo-build)
#   NEMO_SRC             merged source tree to sync with (default: ~/nemo-patched-src,
#                        prepared by nemo-update.sh)
#   NEMO_FEATURE_SYMBOL  symbol that proves the patch is installed
#                        (default: nemo_window_dnd_source_press)
#   NEMO_FORK            fork URL used in the "how to get sources" hint

LOCAL_SRC="${NEMO_LOCAL_SRC:-$HOME/nemo-build}"   # local copy of the patched branch
SRC_DIR="${NEMO_SRC:-$HOME/nemo-patched-src}"     # merged tree maintained by nemo-update.sh
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

# --- Sources: a local copy that mirrors the merged tree from NEMO_SRC -----
# Create the local copy on the first run (only if the merged tree is
# readable; otherwise report honestly what to do).
if [ ! -d "$LOCAL_SRC/.git" ]; then
	if [ -d "$SRC_DIR/.git" ]; then
		echo "==> Creating the local copy: $SRC_DIR -> $LOCAL_SRC"
		git clone -q "$SRC_DIR" "$LOCAL_SRC"
		mkdir -p "$LOCAL_SRC/.git/info"
		grep -qxF 'builddir/' "$LOCAL_SRC/.git/info/exclude" 2>/dev/null \
			|| echo 'builddir/' >> "$LOCAL_SRC/.git/info/exclude"
	else
		echo "    No local copy at $LOCAL_SRC and the merged tree at $SRC_DIR is unavailable." >&2
		echo "    Run ./nemo-update.sh first — it prepares $SRC_DIR," >&2
		echo "    or clone the patched branch yourself:" >&2
		echo "        git clone --branch <branch> $FORK $SRC_DIR" >&2
		exit 1
	fi
fi

# Re-sync on every run: the build must contain the latest Nemo version with
# the functionality merged by nemo-update.sh, not a stale snapshot.
echo "==> Syncing the local copy with $SRC_DIR..."
git -C "$LOCAL_SRC" remote set-url merged "$SRC_DIR" 2>/dev/null \
	|| git -C "$LOCAL_SRC" remote add merged "$SRC_DIR"

if git -C "$LOCAL_SRC" fetch -q merged build 2>/dev/null; then
	# Uncommitted work must survive the sync: stash it, reset, put it back.
	STASH_NAME=
	if [ -n "$(git -C "$LOCAL_SRC" status --porcelain)" ]; then
		STASH_NAME="build_and_install backup $(date +%F_%H:%M:%S)"
		STASHES_BEFORE=$(git -C "$LOCAL_SRC" stash list | wc -l)
		git -C "$LOCAL_SRC" stash push -q -m "$STASH_NAME" || true
		# push creates an entry only for tracked changes; untracked files
		# stay in place by themselves and must not trigger a pop later
		if [ "$(git -C "$LOCAL_SRC" stash list | wc -l)" -le "$STASHES_BEFORE" ]; then
			STASH_NAME=
		else
			echo "    Uncommitted changes found — stashed them as '$STASH_NAME'"
		fi
	fi

	# Commits that are not in the merged tree would be lost by the reset —
	# keep them on a backup branch first.
	if ! git -C "$LOCAL_SRC" merge-base --is-ancestor HEAD FETCH_HEAD 2>/dev/null; then
		BACKUP="backup/local-$(date +%Y%m%d-%H%M%S)"
		echo "    The local copy has commits that are not in the merged tree — kept at $BACKUP"
		git -C "$LOCAL_SRC" branch -q "$BACKUP"
	fi

	git -C "$LOCAL_SRC" reset --hard -q FETCH_HEAD

	if [ -n "$STASH_NAME" ]; then
		if git -C "$LOCAL_SRC" stash pop -q 2>/dev/null; then
			echo "    Your uncommitted changes are kept."
			echo "    Run ./nemo-update.sh to merge them into the new version."
		else
			git -C "$LOCAL_SRC" reset --hard -q   # drop conflict markers
			echo "    WARNING: your uncommitted changes do not apply to the new version." >&2
			echo "             They are safe in the stash:" >&2
			echo "                 git -C $LOCAL_SRC stash list" >&2
			echo "             Run ./nemo-update.sh — it merges local changes properly." >&2
		fi
	fi
else
	echo "    warning: could not fetch the merged tree from $SRC_DIR — building the local copy as is"
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
