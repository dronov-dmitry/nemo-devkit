#!/bin/bash
#
# nemo-update.sh — проверяет, актуальна ли установленная копия Nemo, и если нет —
#                  обновляет её до последней версии linuxmint/nemo, накатывает
#                  патч из вашего форка (окно Nemo не перекрывает цель
#                  перетаскивания, терминал не вылезает наверх при начале драга)
#                  и устанавливает.
#
# Запуск без флагов — интерактивный: скрипт сам определяет состояние и
# предлагает выбор. Флаги оставлены для автоматизации (они вопросов не задают).
#
#   ./nemo-update.sh              анализ + меню (ничего не делает, пока не выбрали)
#   ./nemo-update.sh --check      только показать состояние; коды возврата:
#                                   0 — всё на месте
#                                   1 — требуется обновление/патч
#                                   2 — не удалось определить (нет сети)
#   ./nemo-update.sh --yes        обновить и установить без вопросов
#   ./nemo-update.sh --no-install только обновить и собрать, не устанавливать
#   ./nemo-update.sh --restart    обновить, установить и перезапустить Nemo
#
# Переменные окружения:
#   NEMO_SRC     каталог-песочница для исходников (по умолчанию ~/nemo-patched-src)
#   NEMO_FORK    адрес вашего форка
#   NEMO_BRANCH  ветка с патчем
#   NEMO_UPSTREAM адрес репозитория апстрима
#   NEMO_RAW      откуда брать meson.build апстрима для определения версии
#   NEMO_INSTALLED путь к проверяемому бинарнику (по умолчанию /usr/bin/nemo)
#
set -euo pipefail

UPSTREAM_URL=${NEMO_UPSTREAM:-https://github.com/linuxmint/nemo.git}
RAW_UPSTREAM=${NEMO_RAW:-https://raw.githubusercontent.com/linuxmint/nemo/master/meson.build}
FORK=${NEMO_FORK:-https://github.com/dronov-dmitry/nemo.git}
BRANCH=${NEMO_BRANCH:-dnd-keep-drop-target-visible}
SRC=${NEMO_SRC:-$HOME/nemo-patched-src}
BUILD="$SRC/builddir"
FEATURE_SYMBOL=nemo_window_dnd_source_press
INSTALLED_BIN=${NEMO_INSTALLED:-/usr/bin/nemo}

MODE=interactive
for arg in "$@"; do
    case "$arg" in
        --check)      MODE=check ;;
        --yes|-y)     MODE=install ;;
        --no-install) MODE=build ;;
        --restart)    MODE=install_restart ;;
        -h|--help)    sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "неизвестный аргумент: $arg (см. --help)" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Анализ состояния
# ---------------------------------------------------------------------------
installed_version() {
    # sed читает весь вход, в отличие от head -q/grep -q: при set -o pipefail
    # ранний выход потребителя роняет nm/curl по SIGPIPE и ломает результат.
    [ -x "$INSTALLED_BIN" ] || return 0
    "$INSTALLED_BIN" --version 2>/dev/null | sed -n '1s/^nemo[[:space:]]*//p' || true
}

upstream_version() {
    curl -fsSL --max-time 20 "$RAW_UPSTREAM" 2>/dev/null \
        | sed -n "s/^project('nemo', 'c', version : '\([^']*\)'.*/\1/p" \
        || true
}

has_feature() {   # $1 = путь к бинарнику
    [ -e "$1" ] || return 1
    # grep -c дочитает весь вывод nm, поэтому SIGPIPE не будет, а пустой
    # результат (нет символа) корректно даст отрицательный ответ.
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
else                                                  STATE=ok
fi

print_status() {
    echo "  установлено : ${INSTALLED:-Nemo не установлен}"
    echo "  последняя   : ${UPSTREAM:-<не удалось определить — нет сети?>} (linuxmint/nemo master)"
    echo "  патч ($BRANCH) : $([[ "$PATCH" == yes ]] && echo установлен || echo отсутствует)"
}

case "$STATE" in
    ok)            echo "Статус: ВСЁ НА МЕСТЕ." ;;
    outdated)      echo "Статус: установлена ДРУГАЯ версия — требуется обновление." ;;
    no_patch)      echo "Статус: версия совпадает, но ПАТЧ НЕ УСТАНОВЛЕН." ;;
    not_installed) echo "Статус: Nemo НЕ УСТАНОВЛЕН." ;;
    unknown)       echo "Статус: не удалось определить последнюю версию (нет сети?)."
                   echo "         Установлено: ${INSTALLED:-Nemo не установлен}; патч: $PATCH" ;;
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
# Выбор действия
# ---------------------------------------------------------------------------
CHOICE=install
if [ "$MODE" = "interactive" ]; then
    case "$STATE" in
        ok)
            echo "Что сделать?"
            echo "  1) Ничего не делать (выход)"
            echo "  2) Пересобрать и установить заново"
            printf "Выбор [1]: "; read -r c || true; c=${c:-1}
            [ "$c" = "2" ] && CHOICE=install || CHOICE=quit
            ;;
        unknown)
            echo "Что сделать?"
            echo "  1) Обновить как обычно (потребуется сеть)"
            echo "  2) Выход"
            printf "Выбор [1]: "; read -r c || true; c=${c:-1}
            [ "$c" = "2" ] && CHOICE=quit || CHOICE=install
            ;;
        no_patch)
            echo "Что сделать?"
            echo "  1) Пересобрать текущую версию с патчем и установить"
            echo "  2) Сначала только собрать, без установки"
            echo "  3) Выход"
            printf "Выбор [1]: "; read -r c || true; c=${c:-1}
            case "$c" in
                2) CHOICE=build ;;
                3) CHOICE=quit ;;
                *) CHOICE=install ;;
            esac
            ;;
        *)
            echo "Что сделать?"
            echo "  1) Обновить до последней версии (+ патч) и установить"
            echo "  2) Сначала только собрать, без установки"
            echo "  3) Выход"
            printf "Выбор [1]: "; read -r c || true; c=${c:-1}
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
    echo "Ничего не делаю."
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Исходники: форк с патчем + апстрим
# ---------------------------------------------------------------------------
if [ ! -d "$SRC/.git" ]; then
    echo "==> Клонирую форк $FORK (ветка $BRANCH) → $SRC"
    git clone --branch "$BRANCH" "$FORK" "$SRC"
else
    echo "==> Обновляю форк в $SRC"
    git -C "$SRC" remote set-url origin "$FORK" 2>/dev/null || true
    git -C "$SRC" fetch origin "$BRANCH"
    git -C "$SRC" checkout -B "$BRANCH" "origin/$BRANCH"
fi

echo "==> Подключаю апстрим и забираю последний master"
git -C "$SRC" remote get-url upstream >/dev/null 2>&1 \
    || git -C "$SRC" remote add upstream "$UPSTREAM_URL"
git -C "$SRC" fetch upstream master

# коммиты накатываем даже если identity в системе не настроен
git -C "$SRC" config user.name  >/dev/null 2>&1 || git -C "$SRC" config user.name  "nemo-local"
git -C "$SRC" config user.email >/dev/null 2>&1 || git -C "$SRC" config user.email "nemo-local@localhost"

UP_SHA=$(git -C "$SRC" rev-parse --short upstream/master)
UP_VER=$(git -C "$SRC" show upstream/master:meson.build \
        | sed -n "s/^project('nemo', 'c', version : '\([^']*\)'.*/\1/p")
echo "==> Апстрим: master @ $UP_SHA (nemo $UP_VER)"

# ---------------------------------------------------------------------------
# 2. Накат патча из вашей ветки
# ---------------------------------------------------------------------------
COMMITS=$(git -C "$SRC" rev-list --reverse "upstream/master..$BRANCH")

if [ -z "$COMMITS" ]; then
    echo "==> Ветка $BRANCH не содержит коммитов вне апстрима."
    echo "    (функционал, возможно, уже принят в linuxmint/nemo — проверьте)"
else
    echo "==> Коммиты, которые будут накатаны поверх апстрима:"
    while read -r c; do
        [ -n "$c" ] && echo "      $(git -C "$SRC" log -1 --format='%h %s' "$c")"
    done <<< "$COMMITS"
fi

echo "==> Готовлю рабочую ветку build от upstream/master"
git -C "$SRC" checkout -B build upstream/master

if [ -n "$COMMITS" ]; then
    echo "==> Накатываю патч (cherry-pick)..."
    # shellcheck disable=SC2086
    if ! git -C "$SRC" cherry-pick $COMMITS; then
        cat >&2 <<EOF

!! Конфликт: апстрим изменился в тех же местах, что и патч.

   Разрешите вручную:
       cd $SRC
       git status                 # какие файлы конфликтуют
       ...                        # поправить
       git add <файлы>
       git cherry-pick --continue

   Или откатитесь:
       git cherry-pick --abort

   После правки закоммитьте её в ветку $BRANCH своего форка —
   следующий запуск скрипта накатит уже исправленную версию.
EOF
        exit 1
    fi
fi

git -C "$SRC" grep -q "$FEATURE_SYMBOL" -- 'src/*.c' || {
    echo "!! После наката нужных функций в исходниках нет — патч отстал от апстрима." >&2
    exit 1
}
echo "==> Патч применён (найдена $FEATURE_SYMBOL)"

# ---------------------------------------------------------------------------
# 3. Зависимости (не должны ронять сборку из-за сторонних PPA)
# ---------------------------------------------------------------------------
echo "==> Проверка и установка зависимостей..."
if ! sudo apt-get update -qq; then
    echo "    предупреждение: apt-get update сообщил об ошибке — продолжаю"
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
    || echo "    предупреждение: не удалось доустановить пакеты — продолжаю"

# ---------------------------------------------------------------------------
# 4. Сборка
# ---------------------------------------------------------------------------
# g-ir-scanner падает с "No module named 'distutils.msvccompiler'": в ~/.local
# лежит новый setuptools, у которого этот модуль удалён; системный его содержит.
echo "==> Настройка meson..."
meson setup "$BUILD" "$SRC" --prefix=/usr --reconfigure 2>/dev/null \
    || meson setup "$BUILD" "$SRC" --prefix=/usr

echo "==> Сборка..."
PYTHONNOUSERSITE=1 ninja -C "$BUILD"

if [ "$CHOICE" = "build" ]; then
    echo
    echo "==> Готово (без установки)."
    echo "    Проверить можно так:"
    echo "        nm $BUILD/src/nemo | grep -c $FEATURE_SYMBOL"
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Установка и проверка
# ---------------------------------------------------------------------------
echo "==> Установка (sudo)..."
sudo env PYTHONNOUSERSITE=1 ninja -C "$BUILD" install

echo "==> Проверяю установленный бинарник..."
if has_feature "$INSTALLED_BIN"; then
    echo "    OK: в $INSTALLED_BIN есть $FEATURE_SYMBOL"
else
    echo "    ОШИБКА: символ не найден — установка не удалась" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 6. Итог и перезапуск
# ---------------------------------------------------------------------------
echo
echo "==> Готово."
echo "    Апстрим : nemo $UP_VER @ $UP_SHA"
echo "    Патч    : $BRANCH ($( [ -n "$COMMITS" ] && printf '%s\n' "$COMMITS" | wc -l ) коммит(ов))"

DO_RESTART=0
if [ "$MODE" = "install_restart" ]; then
    DO_RESTART=1
elif [ "$MODE" = "interactive" ]; then
    printf "Перезапустить Nemo сейчас? [д/Н]: "
    read -r r || true
    case "${r:-}" in д|Д|y|Y|yes|да|Да) DO_RESTART=1 ;; esac
fi

if [ "$DO_RESTART" = "1" ]; then
    echo "==> Перезапускаю Nemo..."
    nemo -q 2>/dev/null || true
    sleep 1
    nohup nemo >/dev/null 2>&1 &
    disown || true
    echo "    Nemo перезапущен."
else
    echo "    Перезапустите Nemo для тестирования:"
    echo "        nemo -q && sleep 1 && nemo ~ &"
fi
