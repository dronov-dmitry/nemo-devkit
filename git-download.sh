#!/usr/bin/env bash
#
# Интерактивное скачивание из git: весь репозиторий или одна папка.
# Скрипт спрашивает адрес репозитория, папку, ветку и куда сохранить,
# потом подтверждает скачивание.
#
# Использование:
#   ./git-download.sh
#
# Задайте адрес "по умолчанию" здесь — при запуске останется нажать Enter:
DEFAULT_REPO=""     # напр. https://github.com/user/repo.git
DEFAULT_FOLDER=""   # напр. docs/src (Enter = весь репозиторий)

set -euo pipefail

log()  { printf '\033[1;34m[git-download]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[git-download]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[git-download]\033[0m %s\n' "$*" >&2; }

command -v git >/dev/null 2>&1 || { err "git не установлен"; exit 1; }

# prompt "вопрос" "значение по умолчанию" -> выводит ответ в stdout
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

# д/Н -> 0/1 в ответе
is_yes() {
  case "${1,,}" in
    д|дa|d|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Интерактивный ввод
# ---------------------------------------------------------------------------
repo="$(prompt "Адрес git-репозитория" "$DEFAULT_REPO")"
[[ -n "$repo" ]] || { err "Адрес репозитория не может быть пустым"; exit 1; }

folder="$(prompt "Папка внутри репозитория (Enter — весь репозиторий)" "$DEFAULT_FOLDER")"
folder="${folder#./}"; folder="${folder%/}"   # нормализация пути

repo_name="$(basename "$repo")"
repo_name="${repo_name%.git}"
dest_default="./$repo_name"
[[ -n "$folder" ]] && dest_default="./$(basename "$folder")"

dest="$(prompt "Куда сохранить" "$dest_default")"
branch="$(prompt "Ветка или тег (Enter — по умолчанию)" "")"

# ---------------------------------------------------------------------------
# Подтверждение
# ---------------------------------------------------------------------------
echo
log "Репозиторий: $repo"
[[ -n "$folder" ]] && log "Папка:       $folder"
log "Ветка:       ${branch:-<по умолчанию>}"
log "Сохранить в: $dest"
read -r -p "Скачать? (д/Н): " go || true
is_yes "$go" || { log "Отменено."; exit 0; }

# ---------------------------------------------------------------------------
# Очистка назначения (с подтверждением)
# ---------------------------------------------------------------------------
if [[ -e "$dest" ]]; then
  if [[ -d "$dest" && -z "$(ls -A "$dest" 2>/dev/null)" ]]; then
    rmdir "$dest"
  else
    read -r -p "$dest уже существует и не пуста. Удалить и скачать заново? (д/Н): " ov || true
    is_yes "$ov" || { err "Отменено."; exit 1; }
    rm -rf -- "$dest"
  fi
fi

created=0
fail_cleanup() {
  if [[ "$created" == "1" && -e "$dest" ]]; then
    warn "Ошибка — удаляю неполный $dest"
    rm -rf -- "$dest"
  fi
}
trap fail_cleanup ERR

branch_args=()
[[ -n "$branch" ]] && branch_args=(-b "$branch")

# ---------------------------------------------------------------------------
# Скачивание
# ---------------------------------------------------------------------------
created=1
if [[ -z "$folder" ]]; then
  log "Клонирую весь репозиторий (shallow, --depth 1)..."
  git clone --depth 1 "${branch_args[@]}" "$repo" "$dest"
else
  log "Клонирую только \"$folder\" (sparse-checkout, без лишних файлов)..."
  git clone --depth 1 --filter=blob:none --no-checkout "${branch_args[@]}" "$repo" "$dest"
  git -C "$dest" sparse-checkout init --no-cone
  git -C "$dest" sparse-checkout set "/$folder/"
  git -C "$dest" checkout
fi
created=0
trap - ERR

# ---------------------------------------------------------------------------
# Проверка результата
# ---------------------------------------------------------------------------
if [[ -n "$folder" && ! -e "$dest/$folder" ]]; then
  warn "Папка \"$folder\" не найдена в репозитории (проверьте путь и ветку)."
  warn "Что есть в корне репозитория:"
  git -C "$dest" ls-tree --name-only HEAD | sed 's/^/    /'
  exit 2
fi

log "Готово: $(cd "$dest" && pwd)"
if [[ -n "$folder" ]]; then
  log "Содержимое \"$folder\":"
  find "$dest/$folder" -maxdepth 2 | head -20 | sed 's/^/    /'
else
  log "Содержимое корня:"
  ls "$dest" | head -20 | sed 's/^/    /'
fi
