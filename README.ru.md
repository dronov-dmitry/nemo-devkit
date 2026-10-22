# nemo-devkit

Инструменты вокруг патченной сборки [Nemo](https://github.com/linuxmint/nemo)
(файловый менеджер Cinnamon): сборка, патч, установка и поддержание локальной
копии в актуальном состоянии относительно апстрима.

Сами патчи живут в отдельном форке:
**<https://github.com/dronov-dmitry/nemo>**. Этот репозиторий содержит только
скрипты и файлы патчей — исходники Nemo здесь не дублируются.

[English](README.md) · Русский

## Содержимое

| Путь | Назначение |
| --- | --- |
| `nemo-update.sh` | Основной скрипт: синхронизация форка и апстрима, накат патча, сборка, установка, перезапуск Nemo |
| `build_and_install.sh` | Сборка и установка из уже подготовленной локальной копии исходников |
| `git-download.sh` | Интерактивное shallow-скачивание всего репозитория или одной папки |
| `opencode-session.sh` | Запуск `opencode` в развёрнутом терминале с предложением перезапустить Nemo после выхода |
| `patches/` | Готовые `.patch`-файлы (для `git am` или ревью в PR) |
| `docs/PR_PROMPT.md` | Разбор одного из предложенных фиксов (анализ причины + исправление) |
| `examples/run_install.example.txt` | Пример команды установки локально собранных `.deb` |

## Требования

- Debian/Ubuntu-подобная система с `apt`
- `git`, `meson`, `ninja-build`, `sudo` для установки
- Форк `linuxmint/nemo` с веткой вашего патча

## Быстрый старт

```bash
# 1. Укажите скриптам свой форк и ветку
export NEMO_FORK=https://github.com/dronov-dmitry/nemo.git
export NEMO_BRANCH=dnd-keep-drop-target-visible

# 2. Проверить состояние установленного Nemo (0 — всё хорошо, 1 — нужно обновить)
./nemo-update.sh --check

# 3. Обновить, накатить патч, собрать и установить
./nemo-update.sh --yes

# 4. Или пошагово, в интерактивном режиме
./nemo-update.sh
```

При первом запуске `nemo-update.sh` клонирует форк в `~/nemo-patched-src` и
работает оттуда; далее просто делает fetch и переносит патч на свежий master
апстрима.

## Переменные окружения

| Переменная | По умолчанию | Где используется | Назначение |
| --- | --- | --- | --- |
| `NEMO_FORK` | `https://github.com/dronov-dmitry/nemo.git` | все | Ваш форк |
| `NEMO_BRANCH` | `dnd-keep-drop-target-visible` | `nemo-update.sh` | Ветка с патчем |
| `NEMO_UPSTREAM` | `https://github.com/linuxmint/nemo.git` | `nemo-update.sh` | Репозиторий апстрима |
| `NEMO_SRC` | `~/nemo-patched-src` (в `build_and_install.sh` — `~/nemo-src`) | оба | Песочница для исходников |
| `NEMO_LOCAL_SRC` | `~/nemo-build` | `build_and_install.sh` | Локальная копия, из которой идёт сборка |
| `NEMO_FEATURE_SYMBOL` | `nemo_window_dnd_source_press` | оба | Символ, доказывающий, что патч установлен |
| `NEMO_INSTALLED` | `/usr/bin/nemo` | `nemo-update.sh` | Проверяемый бинарник |
| `NEMO_RAW` | raw `meson.build` от linuxmint/nemo | `nemo-update.sh` | Откуда читать версию апстрима |

`build_and_install.sh` собирает строго из `NEMO_LOCAL_SRC` (по умолчанию на
системном диске), синхронизируя его из `NEMO_SRC` при первом запуске. Так
сборка не идёт напрямую на внешнем диске, который может отваливаться с
ошибками ввода-вывода.

## Накат патчей вручную

Файлы в `patches/` — это те же коммиты ветки форка, выгруженные через
`git format-patch`. Чтобы применить их поверх свежего чекаута апстрима:

```bash
git clone https://github.com/linuxmint/nemo.git
cd nemo
git am /path/to/nemo-devkit/patches/*.patch
```

Чтобы отправить их в апстрим как pull request, запушьте ветку в свой форк и
откройте PR в `linuxmint/nemo`.

## Лицензия

Скрипты предоставлены как есть, в том же духе, что и патчи, которые они
несут. Сами патчи — это вклад в Nemo (GPL-2.0-or-later, см. `linuxmint/nemo`).
