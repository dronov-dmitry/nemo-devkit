#!/bin/bash
set -e

# Внешний Seagate-диск (/dev/sdc2, NTFS через FUSE) периодически отваливается
# с ошибками ввода-вывода (EIO, getcwd/output-error) — собирать на нём нельзя.
# Поэтому скрипт собирает и инсталлирует строго из локальной копии исходников
# /home/kat/nemo-build (системный диск). Скрипт можно запускать из любого
# каталога, в том числе из «упавшего» каталога на внешнем диске.

LOCAL_SRC=/home/kat/nemo-build   # локальная копия патченной ветки
DRIVE_SRC="/media/kat/Seagate5-2/00_Opensource/01_NEMO/nemo"
BUILD_DIR="$LOCAL_SRC/builddir"
FEATURE_SYMBOL=nemo_window_dnd_source_press

echo "==> Проверка и установка зависимостей..."
# Зависимости ставятся здесь для самослужбы, но сборка не должна рушиться из-за
# сторонних репозиториев: сломанный PPA даёт ненулевой код возврата у
# apt-get update, а set -e на этом останавливал весь скрипт до сборки.
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

# Если локальной копии ещё нет — копируем её с внешнего диска (только если
# диск в этот момент читается; иначе честно сообщаем, что делать).
if [ ! -d "$LOCAL_SRC/.git" ]; then
	if [ -d "$DRIVE_SRC/.git" ]; then
		echo "==> Создаю локальную копию исходников: $DRIVE_SRC -> $LOCAL_SRC"
		mkdir -p "$LOCAL_SRC"
		rsync -a --exclude builddir "$DRIVE_SRC/" "$LOCAL_SRC/" \
			|| { echo "    rsync не удался (диск недоступен)" >&2; exit 1; }
	else
		echo "    Локальной копии $LOCAL_SRC нет, а $DRIVE_SRC сейчас недоступен." >&2
		echo "    Восстановите внешний диск и запустите скрипт снова." >&2
		exit 1
	fi
fi

# Донастройка, если builddir ещё не создан.
if [ ! -f "$BUILD_DIR/build.ninja" ]; then
	echo "==> Настройка meson (локально)..."
	meson setup "$BUILD_DIR" "$LOCAL_SRC" --prefix=/usr
fi

echo "==> Сборка (локально)..."
# g-ir-scanner падает с "No module named 'distutils.msvccompiler'": в ~/.local
# лежит setuptools 83, у которого этот модуль удалён.  Системный setuptools
# (68) его содержит, поэтому отключаем user site-packages для сборки.
PYTHONNOUSERSITE=1 ninja -C "$BUILD_DIR"

echo "==> Установка (sudo)..."
sudo env PYTHONNOUSERSITE=1 ninja -C "$BUILD_DIR" install

echo "==> Проверка установленного бинарника..."
echo "    $(nemo --version 2>/dev/null | head -1 || echo 'nemo не запускается')"
if nm /usr/bin/nemo 2>/dev/null | grep -q "$FEATURE_SYMBOL"; then
	echo "    OK: патч установлен ($FEATURE_SYMBOL найден в /usr/bin/nemo)"
else
	echo "    ОШИБКА: символ $FEATURE_SYMBOL не найден в /usr/bin/nemo" >&2
	exit 1
fi

echo "==> Готово!"

printf "Перезапустить Nemo сейчас? [д/Н]: "
read -r r || true
case "${r:-}" in
	д|Д|y|Y|yes|да|Да)
		echo "==> Перезапускаю Nemo..."
		nemo -q 2>/dev/null || true
		sleep 1
		nohup nemo >/dev/null 2>&1 &
		disown || true
		echo "    Nemo перезапущен."
		;;
	*)
		echo "    Перезапустите Nemo для тестирования:"
		echo "        nemo -q && sleep 1 && nemo ~ &"
		;;
esac