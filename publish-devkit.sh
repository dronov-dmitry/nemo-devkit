#!/usr/bin/env bash
#
# publish-devkit.sh
#
# Publishes the nemo-devkit repository (this folder) to GitHub:
#
#   1. Clones dronov-dmitry/nemo-devkit into a temporary directory
#   2. Copies the contents of this folder over it, EXCLUDING:
#        - ./nemo          (the clone of the nemo fork, published by publish-nemo.sh)
#        - ./.git          (the clone's own git metadata)
#   3. Shows what changed and asks for a commit message
#   4. Commits and pushes to the devkit repository
#
# Nothing is deleted on the remote side: files that exist in the devkit but are
# absent locally (README.md, docs/, examples/ ...) are left untouched and listed
# as a notice, so a local rename cannot wipe the repository history.
#
# How to run:
#   ./publish-devkit.sh
#
# No environment variables required. Git credentials for github.com must
# already be configured (credential helper or SSH key).

set -euo pipefail

DEVKIT_URL="https://github.com/dronov-dmitry/nemo-devkit.git"
# Files and directories never copied into the devkit.
EXCLUDE_ITEMS=("nemo" ".git")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
            "")         [ "$def" = "y" ] && return 0 || return 1 ;;
            y|yes|д|да) return 0 ;;
            n|no|н|нет) return 1 ;;
            *)          echo "    Please answer y or n." ;;
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

# Refuse to run if this folder somehow became a git repo itself: in that case
# publishing must go through git directly, and copying it would be wrong.
if git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    pause_exit "ERROR: '$SCRIPT_DIR' is a git repository. Use plain 'git push' there instead."
fi

# --- Clone the devkit --------------------------------------------------------

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:-}"' EXIT
CLONE="$TMP/nemo-devkit"

echo "==> Cloning $DEVKIT_URL ..."
git clone --quiet "$DEVKIT_URL" "$CLONE" || pause_exit "ERROR: failed to clone the devkit."

BRANCH=$(git -C "$CLONE" symbolic-ref --short HEAD)
echo "==> Devkit branch: $BRANCH"

# --- Copy this folder over the clone -----------------------------------------

echo "==> Copying the contents of $SCRIPT_DIR (excluding: ${EXCLUDE_ITEMS[*]}) ..."
EXCLUDE_ARGS=()
for item in "${EXCLUDE_ITEMS[@]}"; do
    EXCLUDE_ARGS+=("--exclude=./$item")
done

# tar preserves permissions and copies hidden files as well; the clone's own
# .git is excluded so the remote history stays intact. The operation cluster
# (-cf) must come before -C: GNU tar does not recognise it the other way round.
tar cf - -C "$SCRIPT_DIR" "${EXCLUDE_ARGS[@]}" . | tar xf - -C "$CLONE"

# --- Show what changed -------------------------------------------------------

cd "$CLONE"
git add -A

echo
echo "==> Changes to be published:"
git diff --cached --stat | sed 's/^/    /'
echo
git diff --cached --name-status | sed 's/^/    /'

# Files kept from the remote because they are missing locally — informative only.
MISSING=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -e "$SCRIPT_DIR/$f" ]; then
        MISSING="$MISSING    $f"$'\n'
    fi
done < <(git ls-files)

if [ -n "$MISSING" ]; then
    echo
    echo "==> Notice: these files exist in the devkit but not locally."
    echo "    They are NOT deleted and stay as they are:"
    printf '%s' "$MISSING"
fi

if git diff --cached --quiet; then
    echo ""
    echo "==> Nothing to publish: the devkit is already up to date."
    read -r -p "Press Enter to close this window..." || true
    exit 0
fi

# --- Commit ------------------------------------------------------------------

echo
if ! ask "Commit these changes?" y; then
    abort
fi

DEFAULT_MSG="Sync scripts and patches"
printf "Commit message [%s]: " "$DEFAULT_MSG"
MSG=""
IFS= read -r MSG || true
[ -n "$MSG" ] || MSG="$DEFAULT_MSG"

# Commit even if the git identity is not configured system-wide.
git config user.name  >/dev/null 2>&1 || git config user.name  "nemo-local"
git config user.email >/dev/null 2>&1 || git config user.email "nemo-local@localhost"

git commit -q -m "$MSG" || pause_exit "ERROR: git commit failed."
echo "==> Committed: $MSG"

# --- Push --------------------------------------------------------------------

echo
if ! ask "Push to origin/$BRANCH?" y; then
    echo "==> Local commits were NOT pushed to GitHub."
    abort
fi

echo "==> Pushing to origin/$BRANCH ..."
if ! git push -u origin "$BRANCH" 2>&1 | sed 's/^/    /'; then
    echo "    Push rejected, trying 'git pull --rebase' ..."
    git pull --rebase -q origin "$BRANCH" \
        || pause_exit "ERROR: rebase failed, resolve conflicts manually (git status)."
    git push -u origin "$BRANCH" 2>&1 | sed 's/^/    /' \
        || pause_exit "ERROR: push failed after rebase."
fi

echo
echo "=========================================================="
echo "  Devkit published: $DEVKIT_URL (branch $BRANCH)"
echo ""
echo "  To get it on another computer:"
echo "      git clone $DEVKIT_URL"
echo "=========================================================="
read -r -p "Press Enter to close this window..." || true
exit 0
