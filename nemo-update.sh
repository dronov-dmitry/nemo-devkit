#!/bin/bash
#
# nemo-update.sh — checks whether the installed copy of Nemo is up to date,
#                  and if not — updates it to the latest linuxmint/nemo,
#                  applies the patch from your fork (the Nemo window no
#                  longer covers the drag target, the terminal no longer
#                  pops on top when a drag starts), CARRIES OVER the locally
#                  built functionality (uncommitted changes in the local
#                  build copy, e.g. ~/nemo-build) and installs it.
#
# Run without flags — interactive: the script detects the state and offers
# choices. Flags are kept for automation (they never ask questions).
#
#   ./nemo-update.sh               analysis + menu (does nothing until you choose)
#   ./nemo-update.sh --check       only show the state; exit codes:
#                                    0 — everything is in place
#                                    1 — update/patch needed
#                                    2 — could not determine (no network)
#   ./nemo-update.sh --yes         update and install without questions
#   ./nemo-update.sh --no-install  update and build only, do not install
#   ./nemo-update.sh --restart     update, install and restart Nemo
#
# Environment variables:
#   NEMO_SRC       sandbox directory for the sources (default: ~/nemo-patched-src)
#   NEMO_LOCAL_SRC local build copy (default: ~/nemo-build). Its uncommitted
#                  changes are treated as "local functionality": they are
#                  applied on top of the new version and committed, so an
#                  update never drops them. After a successful install the
#                  copy is synced with the merged tree.
#   NEMO_LOCAL_PATCH where to save the extracted local changes
#                  (default: ~/nemo-local-features.patch)
#   NEMO_FORK      URL of your fork
#   NEMO_BRANCH    branch with the patch
#   NEMO_UPSTREAM  URL of the upstream repository
#   NEMO_RAW       where to fetch upstream meson.build to detect the version
#   NEMO_INSTALLED path to the binary to check (default: /usr/bin/nemo)
#
set -euo pipefail

UPSTREAM_URL=${NEMO_UPSTREAM:-https://github.com/linuxmint/nemo.git}
RAW_UPSTREAM=${NEMO_RAW:-https://raw.githubusercontent.com/linuxmint/nemo/master/meson.build}
FORK=${NEMO_FORK:-https://github.com/dronov-dmitry/nemo.git}
BRANCH=${NEMO_BRANCH:-dnd-keep-drop-target-visible}
SRC=${NEMO_SRC:-$HOME/nemo-patched-src}
BUILD="$SRC/builddir"
FEATURE_SYMBOL=${NEMO_FEATURE_SYMBOL:-nemo_window_dnd_source_press}
INSTALLED_BIN=${NEMO_INSTALLED:-/usr/bin/nemo}
LOCAL_SRC=${NEMO_LOCAL_SRC:-$HOME/nemo-build}
LOCAL_PATCH_FILE=${NEMO_LOCAL_PATCH:-$HOME/nemo-local-features.patch}
LOCAL_CARRIED=no

MODE=interactive
for arg in "$@"; do
    case "$arg" in
        --check)      MODE=check ;;
        --yes|-y)     MODE=install ;;
        --no-install) MODE=build ;;
        --restart)    MODE=install_restart ;;
        -h|--help)    awk 'NR>1 && /^set -euo/{exit} NR>1{print}' "$0"; exit 0 ;;
        *) echo "unknown argument: $arg (see --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# State analysis
# ---------------------------------------------------------------------------
installed_version() {
    # sed reads the whole input, unlike head -q/grep -q: with set -o pipefail
    # an early exit by the consumer kills nm/curl with SIGPIPE and breaks the result.
    [ -x "$INSTALLED_BIN" ] || return 0
    "$INSTALLED_BIN" --version 2>/dev/null | sed -n '1s/^nemo[[:space:]]*//p' || true
}

upstream_version() {
    curl -fsSL --max-time 20 "$RAW_UPSTREAM" 2>/dev/null \
        | sed -n "s/^project('nemo', 'c', version : '\([^']*\)'.*/\1/p" \
        || true
}

has_feature() {   # $1 = path to the binary
    [ -e "$1" ] || return 1
    # grep -c reads all of nm output, so there is no SIGPIPE, and an empty
    # result (symbol missing) correctly gives a negative answer.
    local n
    n=$(nm "$1" 2>/dev/null | grep -c "$FEATURE_SYMBOL" || true)
    [ "${n:-0}" -gt 0 ]
}

INSTALLED=$(installed_version)
UPSTREAM=$(upstream_version)
if [ -n "${INSTALLED:-}" ] && has_feature "$INSTALLED_BIN"; then
    PATCH=yes
else
    PATCH=no
fi

if [ -z "${INSTALLED:-}" ]; then                    STATE=not_installed
elif [ -z "${UPSTREAM:-}" ]; then                    STATE=unknown
elif [ "$INSTALLED" != "$UPSTREAM" ]; then           STATE=outdated
elif [ "$PATCH" = "no" ]; then                       STATE=no_patch
else                                                 STATE=ok
fi

print_status() {
    echo "  installed : ${INSTALLED:-Nemo is not installed}"
    echo "  latest    : ${UPSTREAM:-<could not determine — no network?>} (linuxmint/nemo master)"
    echo "  patch ($BRANCH) : $([[ "$PATCH" == yes ]] && echo installed || echo missing)"
}

case "$STATE" in
    ok)            echo "Status: EVERYTHING IS IN PLACE." ;;
    outdated)      echo "Status: a DIFFERENT version is installed — an update is needed." ;;
    no_patch)      echo "Status: version matches, but the PATCH IS NOT INSTALLED." ;;
    not_installed) echo "Status: Nemo IS NOT INSTALLED." ;;
    unknown)       echo "Status: could not determine the latest version (no network?)."
                   echo "         Installed: ${INSTALLED:-Nemo is not installed}; patch: $PATCH" ;;
esac
print_status
echo

if [ "$MODE" = "check" ]; then
    case "$STATE" in
        ok) exit 0 ;;
        unknown) exit 2 ;;
        *) exit 1 ;;
    esac
fi

# ---------------------------------------------------------------------------
# Choose an action
# ---------------------------------------------------------------------------
CHOICE=install
if [ "$MODE" = "interactive" ]; then
    case "$STATE" in
        ok)
            echo "What to do?"
            echo "  1) Nothing (quit)"
            echo "  2) Rebuild and reinstall"
            printf "Choice [1]: "; read -r c || true; c=${c:-1}
            [ "$c" = "2" ] && CHOICE=install || CHOICE=quit
            ;;
        unknown)
            echo "What to do?"
            echo "  1) Update as usual (requires network)"
            echo "  2) Quit"
            printf "Choice [1]: "; read -r c || true; c=${c:-1}
            [ "$c" = "2" ] && CHOICE=quit || CHOICE=install
            ;;
        no_patch)
            echo "What to do?"
            echo "  1) Rebuild the current version with the patch and install"
            echo "  2) Build only, without installing"
            echo "  3) Quit"
            printf "Choice [1]: "; read -r c || true; c=${c:-1}
            case "$c" in
                2) CHOICE=build ;;
                3) CHOICE=quit ;;
                *) CHOICE=install ;;
            esac
            ;;
        *)
            echo "What to do?"
            echo "  1) Update to the latest version (+ patch) and install"
            echo "  2) Build only, without installing"
            echo "  3) Quit"
            printf "Choice [1]: "; read -r c || true; c=${c:-1}
            case "$c" in
                2) CHOICE=build ;;
                3) CHOICE=quit ;;
                *) CHOICE=install ;;
            esac
            ;;
    esac
    echo
elif [ "$MODE" = "build" ]; then
    CHOICE=build
elif [ "$MODE" = "install" ] || [ "$MODE" = "install_restart" ]; then
    CHOICE=install
fi

if [ "$CHOICE" = "quit" ]; then
    echo "Nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Sources: fork with the patch + upstream
# ---------------------------------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
    echo "==> Cloning fork $FORK (branch $BRANCH) -> $SRC"
    git clone --branch "$BRANCH" "$FORK" "$SRC"
else
    echo "==> Updating the fork in $SRC"
    git -C "$SRC" remote set-url origin "$FORK" 2>/dev/null || true
    git -C "$SRC" fetch origin "$BRANCH"
    git -C "$SRC" checkout -B "$BRANCH" "origin/$BRANCH"
fi

echo "==> Adding upstream and fetching the latest master"
git -C "$SRC" remote get-url upstream >/dev/null 2>&1 \
    || git -C "$SRC" remote add upstream "$UPSTREAM_URL"
git -C "$SRC" fetch upstream master

# commits are applied even if the git identity is not configured
git -C "$SRC" config user.name  >/dev/null 2>&1 || git -C "$SRC" config user.name  "nemo-local"
git -C "$SRC" config user.email >/dev/null 2>&1 || git -C "$SRC" config user.email "nemo-local@localhost"

UP_SHA=$(git -C "$SRC" rev-parse --short upstream/master)
UP_VER=$(git -C "$SRC" show upstream/master:meson.build \
        | sed -n "s/^project('nemo', 'c', version : '\([^']*\)'.*/\1/p")
echo "==> Upstream: master @ $UP_SHA (nemo $UP_VER)"

# ---------------------------------------------------------------------------
# 2. Apply the patch from your branch
# ---------------------------------------------------------------------------
COMMITS=$(git -C "$SRC" rev-list --reverse "upstream/master..$BRANCH")

if [ -z "$COMMITS" ]; then
    echo "==> Branch $BRANCH has no commits outside upstream."
    echo "    (the feature may already be merged in linuxmint/nemo — check)"
else
    echo "==> Commits that will be applied on top of upstream:"
    while read -r c; do
        [ -n "$c" ] && echo "      $(git -C "$SRC" log -1 --format='%h %s' "$c")"
    done <<< "$COMMITS"
fi

echo "==> Preparing the build branch from upstream/master"
git -C "$SRC" checkout -B build upstream/master

if [ -n "$COMMITS" ]; then
    echo "==> Applying the patch (cherry-pick)..."
    # shellcheck disable=SC2086
    if ! git -C "$SRC" cherry-pick $COMMITS; then
        cat >&2 <<EOF

!! Conflict: upstream changed the same places as the patch.

   Resolve it manually:
       cd $SRC
       git status                 # which files conflict
       ...                        # fix them
       git add <files>
       git cherry-pick --continue

   Or roll back:
       git cherry-pick --abort

   After fixing, commit the result to the $BRANCH branch of your fork —
   the next run of this script will apply the fixed version.
EOF
        exit 1
    fi
fi

git -C "$SRC" grep -q "$FEATURE_SYMBOL" -- 'src/*.c' || {
    echo "!! After applying, the needed functions are missing in the sources — the patch fell behind upstream." >&2
    exit 1
}
echo "==> Patch applied ($FEATURE_SYMBOL found)"

# ---------------------------------------------------------------------------
# 2b. Carry over the locally built functionality
# ---------------------------------------------------------------------------
# The local build copy (the one build_and_install.sh builds from) may hold
# extra functionality that exists nowhere else yet: uncommitted changes in
# its working tree. They are extracted as a patch and applied on top of the
# build branch, so an update never silently drops them.
if [ "$LOCAL_SRC" = "$SRC" ] || [ ! -d "$LOCAL_SRC/.git" ]; then
    echo "==> No separate local build copy ($LOCAL_SRC) — nothing to carry over"
elif [ -n "$(git -C "$LOCAL_SRC" status --porcelain 2>/dev/null)" ]; then
    echo "==> Local functionality found in $LOCAL_SRC:"
    # intent-to-add: brand-new untracked files are included in the diff
    git -C "$LOCAL_SRC" add -N . 2>/dev/null || true
    git -C "$LOCAL_SRC" diff HEAD --stat | sed 's/^/      /'
    git -C "$LOCAL_SRC" diff HEAD > "$LOCAL_PATCH_FILE"

    if [ -s "$LOCAL_PATCH_FILE" ]; then
        echo "==> Applying the local functionality on top of the new version..."
        if ! git -C "$SRC" apply --3way "$LOCAL_PATCH_FILE"; then
            cat >&2 <<EOF

!! The local changes from $LOCAL_SRC conflict with the new Nemo version.

   The patch is saved to: $LOCAL_PATCH_FILE
   Nothing is lost: the changes are still uncommitted in $LOCAL_SRC.

   Option 1 — resolve the conflict and keep the functionality:
       cd $SRC
       # fix the files with conflict markers, then:
       git add <files> && git commit
       cd $LOCAL_SRC && git reset --hard    # the changes are consumed

   Option 2 — drop the local changes and continue without them:
       cd $SRC && git reset --hard
       cd $LOCAL_SRC && git checkout -- . && git clean -fd

   Then rerun this script.
EOF
            exit 1
        fi
        # git apply --3way stages the merged files; add the rest explicitly
        while IFS= read -r f; do
            [ -n "$f" ] && git -C "$SRC" add -- "$f"
        done < <(git -C "$LOCAL_SRC" diff HEAD --name-only)
        git -C "$SRC" commit -q -m "local: carry over the functionality from $LOCAL_SRC"
        LOCAL_CARRIED=yes
        echo "==> Local functionality applied and committed"
    fi
else
    echo "==> No uncommitted local changes in $LOCAL_SRC — nothing to carry over"
fi

# ---------------------------------------------------------------------------
# 3. Dependencies (must not break the build because of third-party PPAs)
# ---------------------------------------------------------------------------
echo "==> Checking and installing build dependencies..."
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

# ---------------------------------------------------------------------------
# 4. Build
# ---------------------------------------------------------------------------
# g-ir-scanner crashes with "No module named 'distutils.msvccompiler'": ~/.local
# contains a newer setuptools where this module was removed; the system one has it.
echo "==> Configuring meson..."
meson setup "$BUILD" "$SRC" --prefix=/usr --reconfigure 2>/dev/null \
    || meson setup "$BUILD" "$SRC" --prefix=/usr

echo "==> Building..."
PYTHONNOUSERSITE=1 ninja -C "$BUILD"

if [ "$CHOICE" = "build" ]; then
    echo
    echo "==> Done (not installed)."
    echo "    You can check it like this:"
    echo "        nm $BUILD/src/nemo | grep -c $FEATURE_SYMBOL"
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Install and verify
# ---------------------------------------------------------------------------
echo "==> Installing (sudo)..."
sudo env PYTHONNOUSERSITE=1 ninja -C "$BUILD" install

echo "==> Checking the installed binary..."
if has_feature "$INSTALLED_BIN"; then
    echo "    OK: $INSTALLED_BIN contains $FEATURE_SYMBOL"
else
    echo "    ERROR: symbol not found — installation failed" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 6. Sync the merged tree into the local build copy
# ---------------------------------------------------------------------------
# build_and_install.sh builds from LOCAL_SRC; bring it to the same state, so
# a later rebuild keeps both the new Nemo version and the local functionality.
if [ "$LOCAL_SRC" != "$SRC" ] && [ -d "$LOCAL_SRC/.git" ]; then
    echo "==> Syncing the merged tree into the local build copy: $LOCAL_SRC"
    git -C "$LOCAL_SRC" remote set-url merged "$SRC" 2>/dev/null \
        || git -C "$LOCAL_SRC" remote add merged "$SRC"
    git -C "$LOCAL_SRC" fetch -q merged build
    # The local changes were consumed above (section 2b) — safe to reset.
    git -C "$LOCAL_SRC" reset --hard -q
    git -C "$LOCAL_SRC" checkout -q -B build FETCH_HEAD
    mkdir -p "$LOCAL_SRC/.git/info"
    grep -qxF 'builddir/' "$LOCAL_SRC/.git/info/exclude" 2>/dev/null \
        || echo 'builddir/' >> "$LOCAL_SRC/.git/info/exclude"
    echo "    done: build @ $(git -C "$LOCAL_SRC" rev-parse --short HEAD)"
fi

# ---------------------------------------------------------------------------
# 7. Summary and restart
# ---------------------------------------------------------------------------
echo
echo "==> Done."
echo "    Upstream : nemo $UP_VER @ $UP_SHA"
echo "    Patch    : $BRANCH ($( [ -n "$COMMITS" ] && printf '%s\n' "$COMMITS" | wc -l ) commit(s))"
echo "    Local    : $( [ "$LOCAL_CARRIED" = yes ] && echo "functionality from $LOCAL_SRC carried over" || echo "no local changes to carry over" )"

DO_RESTART=0
if [ "$MODE" = "install_restart" ]; then
    DO_RESTART=1
elif [ "$MODE" = "interactive" ]; then
    printf "Restart Nemo now? [y/N]: "
    read -r r || true
    case "${r:-}" in y|Y|yes|Yes) DO_RESTART=1 ;; esac
fi

if [ "$DO_RESTART" = "1" ]; then
    echo "==> Restarting Nemo..."
    nemo -q 2>/dev/null || true
    sleep 1
    nohup nemo >/dev/null 2>&1 &
    disown || true
    echo "    Nemo restarted."
else
    echo "    Restart Nemo manually to test:"
    echo "        nemo -q && sleep 1 && nemo ~ &"
fi
