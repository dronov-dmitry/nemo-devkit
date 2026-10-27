#!/usr/bin/env bash
#
# publish-nemo.sh
#
# Publishes the patched Nemo sources to GitHub, so that any other computer
# running nemo-update.sh picks the changes up automatically:
#
#   1. Commits the pending changes in ./nemo (branch dnd-keep-drop-target-visible)
#   2. Pushes them to the fork remote (dronov-dmitry/nemo)
#   3. Optionally re-exports patches/ into nemo-devkit and pushes the devkit,
#      so the exported .patch files stay in sync with the fork branch.
#
# Why the fork and not patches/: nemo-update.sh cherry-picks the commits of the
# fork branch onto upstream (rev-list upstream/master..BRANCH). The patches/
# folder is only a git format-patch export for manual application and PR review.
#
# How to run:
#   ./publish-nemo.sh
#
# No environment variables required. Git credentials for github.com must
# already be configured (credential helper or SSH key).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEMO_DIR="$SCRIPT_DIR/nemo"
FORK_REMOTE="fork"
DEVKIT_URL="https://github.com/dronov-dmitry/nemo-devkit.git"

ask() {
    # ask "Question?" y|n  ->  0 = yes, 1 = no (Enter accepts the default)
    local q="$1" def="$2" r hint
    if [ "$def" = "y" ]; then hint="Y/n"; else hint="y/N"; fi
    while true; do
        printf "%s [%s]: " "$q" "$hint"
        if ! IFS= read -r r; then
            echo
            return 1
        fi
        case "${r,,}" in
            "")        [ "$def" = "y" ] && return 0 || return 1 ;;
            y|yes|д|да) return 0 ;;
            n|no|н|нет) return 1 ;;
            *)         echo "    Please answer y or n." ;;
        esac
    done
}

pause_exit() {
    echo ""
    echo "$1" >&2
    read -r -p "Press Enter to close this window..." || true
    exit 1
}

abort() {
    echo ""
    echo "==> Aborted, nothing was published."
    read -r -p "Press Enter to close this window..." || true
    exit 2
}

# --- Safety checks -----------------------------------------------------------

command -v git >/dev/null 2>&1 || pause_exit "ERROR: 'git' is not installed."

[ -d "$NEMO_DIR/.git" ] || pause_exit "ERROR: '$NEMO_DIR' is not a git repository."

if ! git -C "$NEMO_DIR" remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
    pause_exit "ERROR: remote '$FORK_REMOTE' is not set in '$NEMO_DIR'."
fi

BRANCH=$(git -C "$NEMO_DIR" symbolic-ref --short HEAD 2>/dev/null || true)
[ -n "$BRANCH" ] || pause_exit "ERROR: detached HEAD in '$NEMO_DIR', cannot determine branch."

# --- Current state -----------------------------------------------------------

echo "==> Fetching $FORK_REMOTE/$BRANCH ..."
git -C "$NEMO_DIR" fetch "$FORK_REMOTE" "$BRANCH" 2>&1 | sed 's/^/    /'

DIRTY=$(git -C "$NEMO_DIR" status --porcelain | grep -c . || true)
AHEAD=$(git -C "$NEMO_DIR" rev-list --count "$FORK_REMOTE/$BRANCH..HEAD" || echo 0)
BEHIND=$(git -C "$NEMO_DIR" rev-list --count "HEAD..$FORK_REMOTE/$BRANCH" || echo 0)

echo
echo "==> Repository : $(git -C "$NEMO_DIR" remote get-url "$FORK_REMOTE")"
echo "    Directory  : $NEMO_DIR"
echo "    Branch     : $BRANCH"
echo "    Uncommitted: $DIRTY file(s)"
echo "    Unpushed   : $AHEAD commit(s)"
echo "    Behind     : $BEHIND commit(s)"

if [ "$BEHIND" -gt 0 ]; then
    echo ""
    echo "    WARNING: the remote branch is ahead by $BEHIND commit(s)."
    if ! ask "Rebase local commits on top of the remote and continue?" y; then
        abort
    fi
    git -C "$NEMO_DIR" rebase "$FORK_REMOTE/$BRANCH" 2>&1 | sed 's/^/    /' \
        || pause_exit "ERROR: rebase failed, resolve conflicts manually (git status) and re-run."
fi

if [ "$DIRTY" -eq 0 ] && [ "$AHEAD" -eq 0 ]; then
    echo ""
    echo "==> Nothing to publish: working tree is clean and local is in sync."
    read -r -p "Press Enter to close this window..." || true
    exit 0
fi

# --- Commit ------------------------------------------------------------------

if [ "$DIRTY" -gt 0 ]; then
    echo
    echo "==> Changes to be committed:"
    git -C "$NEMO_DIR" add -A
    git -C "$NEMO_DIR" diff --cached --stat | sed 's/^/    /'

    echo
    if ! ask "Commit these changes?" y; then
        abort
    fi

    DEFAULT_MSG="actions: add Copy path to the context menu and the sidebar tree"
    printf "Commit message [%s]: " "$DEFAULT_MSG"
    MSG=""
    IFS= read -r MSG || true
    [ -n "$MSG" ] || MSG="$DEFAULT_MSG"

    git -C "$NEMO_DIR" commit -q -m "$MSG" || pause_exit "ERROR: git commit failed."
    echo "==> Committed: $MSG"
fi

# --- Push --------------------------------------------------------------------

AHEAD=$(git -C "$NEMO_DIR" rev-list --count "$FORK_REMOTE/$BRANCH..HEAD" || echo 0)

echo
if [ "$AHEAD" -eq 0 ]; then
    echo "==> Nothing to push: local branch is in sync with $FORK_REMOTE/$BRANCH."
else
    if ! ask "Push $AHEAD commit(s) to $FORK_REMOTE/$BRANCH?" y; then
        echo "==> Local commits were NOT pushed to GitHub."
        abort
    fi

    echo "==> Pushing to $FORK_REMOTE/$BRANCH ..."
    if ! git -C "$NEMO_DIR" push -u "$FORK_REMOTE" "$BRANCH" 2>&1 | sed 's/^/    /'; then
        echo "    Push rejected, trying 'git pull --rebase' ..."
        git -C "$NEMO_DIR" pull --rebase -q "$FORK_REMOTE" "$BRANCH" \
            || pause_exit "ERROR: rebase failed, resolve conflicts manually (git status)."
        git -C "$NEMO_DIR" push -u "$FORK_REMOTE" "$BRANCH" 2>&1 | sed 's/^/    /' \
            || pause_exit "ERROR: push failed after rebase."
    fi
    echo "==> Pushed to https://github.com/dronov-dmitry/nemo (branch $BRANCH)"
fi

# --- Optional: keep the devkit patches/ export in sync -----------------------

echo
if ask "Also re-export patches/ into nemo-devkit and push it?" y; then
    TMP=$(mktemp -d)
    trap 'rm -rf "${TMP:-}"' EXIT

    echo "==> Cloning $DEVKIT_URL ..."
    git clone --quiet "$DEVKIT_URL" "$TMP/devkit" \
        || pause_exit "ERROR: failed to clone the devkit."

    mkdir -p "$TMP/devkit/patches"
    rm -f "$TMP/devkit/patches/"*.patch

    git -C "$NEMO_DIR" fetch --quiet origin master || true
    echo "==> Exporting commits of $BRANCH (not in upstream master) ..."
    git -C "$NEMO_DIR" format-patch --quiet --outdir "$TMP/devkit/patches" "origin/master..HEAD" \
        || pause_exit "ERROR: git format-patch failed."

    ls -1 "$TMP/devkit/patches" | sed 's/^/    /'

    DEVKIT_BRANCH=$(git -C "$TMP/devkit" symbolic-ref --short HEAD)
    git -C "$TMP/devkit" add -A patches

    if git -C "$TMP/devkit" diff --cached --quiet; then
        echo "==> patches/ is already in sync, nothing to push."
    else
        echo
        echo "==> Devkit changes:"
        git -C "$TMP/devkit" diff --cached --stat | sed 's/^/    /'
        if ask "Commit and push the devkit?" y; then
            git -C "$TMP/devkit" commit -q -m "patches: re-export from fork branch $BRANCH" \
                || pause_exit "ERROR: devkit commit failed."
            git -C "$TMP/devkit" push -u origin "$DEVKIT_BRANCH" 2>&1 | sed 's/^/    /' \
                || pause_exit "ERROR: devkit push failed."
            echo "==> Devkit pushed: https://github.com/dronov-dmitry/nemo-devkit (branch $DEVKIT_BRANCH)"
        else
            echo "==> Devkit was NOT pushed."
        fi
    fi
fi

# --- Done --------------------------------------------------------------------

echo ""
echo "=========================================================="
echo "  Published."
echo ""
echo "  To get it on another computer, run there:"
echo "      ./nemo-update.sh"
echo "  (it will fetch the fork branch and cherry-pick the commits)"
echo "=========================================================="
read -r -p "Press Enter to close this window..." || true
exit 0
