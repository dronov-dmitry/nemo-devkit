#!/bin/bash
# git-publish.sh — interactive publisher for this project on GitHub.
# Stages all changes, asks about commit message and pushes to the existing
# origin (dronov-dmitry/nemo-devkit). Run it without any arguments:
#
#   ./git-publish.sh
#
# Flow: review changes -> commit message -> push.
# Exit codes: 0 — published (or nothing left), 1 — error, 2 — aborted.

set -u

REPO_URL="https://github.com/dronov-dmitry/nemo-devkit"

# ask "Question?" y|n  ->  0 = yes, 1 = no (Enter accepts the default)
ask() {
    local q="$1" def="$2" r hint
    if [ "$def" = "y" ]; then hint="Y/n"; else hint="y/N"; fi
    while true; do
        printf "%s [%s]: " "$q" "$hint"
        if ! IFS= read -r r; then
            echo
            return 1
        fi
        case "${r,,}" in
            "")  [ "$def" = "y" ] && return 0 || return 1 ;;
            y|yes|д|да)   return 0 ;;
            n|no|н|нет)   return 1 ;;
            *)   echo "    Please answer y or n." ;;
        esac
    done
}

abort() {
    echo "==> Aborted, nothing was published."
    exit 2
}

# --- Safety checks ----------------------------------------------------------

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: not a git repository." >&2
    exit 1
fi

BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || true)
if [ -z "$BRANCH" ]; then
    echo "ERROR: detached HEAD, cannot determine branch." >&2
    exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    echo "ERROR: remote 'origin' is not set." >&2
    echo "       Expected: git@github.com:dronov-dmitry/nemo-devkit.git" >&2
    exit 1
fi

# --- Stage everything (files from .gitignore are never touched) -------------

git add -A
STAGED=$(git diff --cached --name-only)
STAGED_N=$(printf '%s' "$STAGED" | grep -c . || true)
AHEAD=$(git rev-list --count "@{upstream}..HEAD" 2>/dev/null || echo 0)

echo "==> Repository : $(git remote get-url origin)"
echo "    Branch     : $BRANCH"
echo "    New changes : $STAGED_N file(s)"
echo "    Unpushed    : $AHEAD commit(s)"

if [ "$STAGED_N" -gt 0 ]; then
    echo
    git diff --cached --stat | sed 's/^/    /'
elif [ "$AHEAD" -eq 0 ]; then
    echo
    echo "==> Nothing to publish: working tree is clean and local is in sync."
    exit 0
fi

# --- Commit -----------------------------------------------------------------

if [ "$STAGED_N" -gt 0 ]; then
    echo
    if ! ask "Commit these changes?" y; then
        abort
    fi

    DEFAULT_MSG="Update $(date '+%Y-%m-%d %H:%M:%S')"
    printf "Commit message [%s]: " "$DEFAULT_MSG"
    if ! IFS= read -r MSG; then
        echo
        abort
    fi
    [ -n "$MSG" ] || MSG="$DEFAULT_MSG"

    if ! git commit -q -m "$MSG"; then
        echo "ERROR: git commit failed." >&2
        exit 1
    fi
    echo "==> Committed: $MSG"
fi

# --- Push (re-sync automatically if the remote has moved) -------------------

echo
if ! ask "Push to origin/$BRANCH?" y; then
    echo "==> Local commits were NOT pushed to GitHub."
    exit 2
fi

echo "==> Pushing to origin/$BRANCH ..."
if ! git push -u origin "$BRANCH" 2>&1 | sed 's/^/    /'; then
    echo "    Push rejected, trying 'git pull --rebase' ..."
    if ! git pull --rebase -q origin "$BRANCH"; then
        echo "ERROR: rebase failed, resolve conflicts manually:" >&2
        echo "       git status" >&2
        exit 1
    fi
    if ! git push -u origin "$BRANCH" 2>&1 | sed 's/^/    /'; then
        echo "ERROR: push failed after rebase." >&2
        exit 1
    fi
fi

echo
echo "==> Published: $REPO_URL"
