#!/usr/bin/env bash
#
# Interactive download from git: the whole repository or a single folder.
# The script asks for the repository URL, folder, branch and destination,
# then confirms the download.
#
# Usage:
#   ./git-download.sh
#
# Set the "default" values here so that at startup you only press Enter:
DEFAULT_REPO=""     # e.g. https://github.com/user/repo.git
DEFAULT_FOLDER=""   # e.g. docs/src (Enter = whole repository)

set -euo pipefail

log()  { printf '\033[1;34m[git-download]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[git-download]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[git-download]\033[0m %s\n' "$*" >&2; }

command -v git >/dev/null 2>&1 || { err "git is not installed"; exit 1; }

# prompt "question" "default value" -> prints the answer to stdout
prompt() {
  local q="$1" def="${2:-}" ans=""
  if [[ -n "$def" ]]; then
    read -r -p "$q [$def]: " ans || true
    ans="${ans:-$def}"
  else
    read -r -p "$q: " ans || true
  fi
  printf '%s' "$ans"
}

# y/n answer -> 0/1
is_yes() {
  case "${1,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Interactive input
# ---------------------------------------------------------------------------
repo="$(prompt "Git repository URL" "$DEFAULT_REPO")"
[[ -n "$repo" ]] || { err "Repository URL cannot be empty"; exit 1; }

folder="$(prompt "Folder inside the repository (Enter — whole repository)" "$DEFAULT_FOLDER")"
folder="${folder#./}"; folder="${folder%/}"   # normalize the path

repo_name="$(basename "$repo")"
repo_name="${repo_name%.git}"
dest_default="./$repo_name"
[[ -n "$folder" ]] && dest_default="./$(basename "$folder")"

dest="$(prompt "Save to" "$dest_default")"
branch="$(prompt "Branch or tag (Enter — default)" "")"

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
echo
log "Repository: $repo"
[[ -n "$folder" ]] && log "Folder:     $folder"
log "Branch:     ${branch:-<default>}"
log "Save to:    $dest"
read -r -p "Download? (y/N): " go || true
is_yes "$go" || { log "Cancelled."; exit 0; }

# ---------------------------------------------------------------------------
# Cleaning the destination (with confirmation)
# ---------------------------------------------------------------------------
if [[ -e "$dest" ]]; then
  if [[ -d "$dest" && -z "$(ls -A "$dest" 2>/dev/null)" ]]; then
    rmdir "$dest"
  else
    read -r -p "$dest already exists and is not empty. Delete and download again? (y/N): " ov || true
    is_yes "$ov" || { err "Cancelled."; exit 1; }
    rm -rf -- "$dest"
  fi
fi

created=0
fail_cleanup() {
  if [[ "$created" == "1" && -e "$dest" ]]; then
    warn "Error — removing incomplete $dest"
    rm -rf -- "$dest"
  fi
}
trap fail_cleanup ERR

branch_args=()
[[ -n "$branch" ]] && branch_args=(-b "$branch")

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
created=1
if [[ -z "$folder" ]]; then
  log "Cloning the whole repository (shallow, --depth 1)..."
  git clone --depth 1 "${branch_args[@]}" "$repo" "$dest"
else
  log "Cloning only \"$folder\" (sparse-checkout, no extra files)..."
  git clone --depth 1 --filter=blob:none --no-checkout "${branch_args[@]}" "$repo" "$dest"
  git -C "$dest" sparse-checkout init --no-cone
  git -C "$dest" sparse-checkout set "/$folder/"
  git -C "$dest" checkout
fi
created=0
trap - ERR

# ---------------------------------------------------------------------------
# Verify the result
# ---------------------------------------------------------------------------
if [[ -n "$folder" && ! -e "$dest/$folder" ]]; then
  warn "Folder \"$folder\" not found in the repository (check the path and branch)."
  warn "What is in the repository root:"
  git -C "$dest" ls-tree --name-only HEAD | sed 's/^/    /'
  exit 2
fi

log "Done: $(cd "$dest" && pwd)"
if [[ -n "$folder" ]]; then
  log "Contents of \"$folder\":"
  find "$dest/$folder" -maxdepth 2 | head -20 | sed 's/^/    /'
else
  log "Contents of the root:"
  ls "$dest" | head -20 | sed 's/^/    /'
fi
