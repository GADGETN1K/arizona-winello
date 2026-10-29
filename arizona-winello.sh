#!/usr/bin/env bash
# arizona-winello: ставит и запускает Arizona Games Launcher на Linux
# (umu-launcher + GE-Proton, отдельный префикс, ярлык в меню).
# По мотивам https://github.com/NelloKudo/osu-winello

set -euo pipefail

APP="arizona"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/arizona-winello"
CFG="$DATA/config.cfg"
BIN="$HOME/.local/bin/$APP"
DESKTOP="${XDG_DATA_HOME:-$HOME/.local/share}/applications/arizona-launcher.desktop"
ICON="$DATA/icon.png"
ARZMARKET_URL="https://github.com/FREYM1337/forumnick/raw/main/ArzMarketInstaller/cache.zip"
MIRRORS=(
    "https://arz-pc1.react-group.tech/Arizona%20Launcher.exe"
    "https://arz-pc.react-group.tech/Arizona%20Launcher.exe"
)
UA="Mozilla/5.0"
WINELAND_REPO="nanomatters/proton-salkim"
COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"

msg()  { printf '\e[1;35m[arizona]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[arizona]\e[0m %s\n' "$*" >&2; }
die()  { printf '\e[1;31m[arizona]\e[0m %s\n' "$*" >&2; exit 1; }

# ---------- конфиг ----------

default_config() {
    local proton="GE-Proton"   # umu сам скачает свежий GE-Proton
    for p in /usr/share/steam/compatibilitytools.d/proton-ge-custom \
             "$HOME"/.local/share/Steam/compatibilitytools.d/GE-Proton*; do
        [[ -x "$p/proton" ]] && proton="$p"
    done
    local wayland_proton=""   # Proton Wineland (форк proton-cachyos с Wayland по умолчанию), если стоит
    for p in "$HOME"/.local/share/Steam/compatibilitytools.d/proton-wineland*; do
        [[ -x "$p/proton" ]] && wayland_proton="$p"
    done
    cat <<EOF
# Конфиг arizona-winello. Править: arizona --edit-config

# Префикс Wine
WINEPREFIX="$DATA/prefix"

# Чем запускать: umu (Proton через umu-run) или wine (системный wine)
RUNNER="umu"

# Путь к Proton или "GE-Proton" (umu скачает и будет обновлять сам)
PROTONPATH="$proton"

# exe лаунчера внутри префикса (находится автоматически после установки)
LAUNCHER_EXE=""

# Аргументы лаунчера. Electron под Wine иногда нужен --no-sandbox
LAUNCHER_ARGS="--no-sandbox"

# Русская локаль, иначе кракозябры в лаунчере и чате
LOCALE="ru_RU.UTF-8"

# Feral GameMode: governor performance и высокие частоты GPU на время игры (1/0)
GAMEMODE="1"

# Оверлей MangoHud с FPS, загрузкой CPU и GPU, температурой (1/0)
MANGOHUD="0"

# Лимит FPS через DXVK (0 = без лимита). На APU лимит под стабильный FPS
# оставляет запас по теплу и TDP, и просадок становится меньше
FPS_LIMIT="0"

# Wayland-драйвер Wine вместо XWayland, только с RUNNER="umu":
#   auto — в Wayland-сессии да, в X11 нет;  1 — всегда, когда есть Wayland;  0 — никогда
WAYLAND="auto"

# Proton для Wayland-режима, например Proton Wineland
# (github.com/nanomatters/proton-salkim). Пусто — тот же PROTONPATH
PROTONPATH_WAYLAND="$wayland_proton"

# Раз в сутки проверять новый релиз Proton Wineland на GitHub и ставить его (1/0)
WINELAND_UPDATE="1"

# Пока запущена игра, давать лаунчеру только свободный CPU (1/0)
IDLE_LAUNCHER="1"

# Доп. переменные окружения через пробел, например "DXVK_HUD=fps PROTON_USE_WINED3D=1"
EXTRA_ENV=""
EOF
}

load_config() {
    [[ -f "$CFG" ]] || { mkdir -p "$DATA"; default_config > "$CFG"; }
    # shellcheck source=/dev/null
    source "$CFG"
}

set_config() { # ключ значение
    local esc=${2//\\/\\\\}; esc=${esc//&/\\&}; esc=${esc//|/\\|}
    sed -i "s|^$1=.*|$1=\"$esc\"|" "$CFG"
}

# ---------- запуск Wine/Proton ----------

# ---------- Proton Wineland ----------

x86_64_level() { # 1–4: какой уровень микроархитектуры x86-64 поддерживает процессор
    local ld lvl
    # glibc сам знает, какие уровни поддерживает CPU: «x86-64-v3 (supported, searched)»
    for ld in /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2 /usr/lib/ld-linux-x86-64.so.2; do
        [[ -x "$ld" ]] || continue
        lvl=$("$ld" --help 2>/dev/null | grep -o 'x86-64-v[234] (supported' | grep -o 'v[234]' | tr -d v | sort -n | tail -n1)
        [[ -n "$lvl" ]] && { echo "$lvl"; return; }
    done
    # запасной путь: флаги из /proc/cpuinfo по определению уровней x86-64 psABI
    local flags; flags=" $(grep -m1 '^flags' /proc/cpuinfo | cut -d: -f2) "
    has() { local f; for f; do [[ "$flags" == *" $f "* ]] || return 1; done; }
    if has avx512f avx512bw avx512cd avx512dq avx512vl && has avx avx2 bmi1 bmi2 f16c fma abm movbe xsave; then echo 4
    elif has avx avx2 bmi1 bmi2 f16c fma abm movbe xsave && has cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3; then echo 3
    elif has cx16 lahf_lm popcnt sse4_1 sse4_2 ssse3; then echo 2
    else echo 1
    fi
}

wineland_flavor() { # у Wineland есть сборки x86_64 и x86_64_v3 (на v4 тоже идёт v3)
    if (( $(x86_64_level) >= 3 )); then echo x86_64_v3; else echo x86_64; fi
}

wineland_latest_url() {
    local url tag
    url=$(curl -fsSL -m 20 --retry 2 -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$WINELAND_REPO/releases/latest" 2>/dev/null |
        grep -o "\"browser_download_url\": *\"[^\"]*-$(wineland_flavor)\.tar\.xz\"" |
        head -n1 | sed 's/.*"\(https[^"]*\)"$/\1/')
    if [[ -z "$url" ]]; then
        # api.github.com бывает недоступен, а github.com отвечает: тег берём из редиректа
        tag=$(curl -fsSIL -m 20 --retry 2 -o /dev/null -w '%{url_effective}' \
            "https://github.com/$WINELAND_REPO/releases/latest" 2>/dev/null)
        tag=${tag##*/tag/}
        [[ "$tag" == wineland-* ]] &&
            url="https://github.com/$WINELAND_REPO/releases/download/$tag/proton-$tag-$(wineland_flavor).tar.xz"
    fi
    echo "$url"
}

update_wineland() {
    local url name dir tmp d
    url=$(wineland_latest_url)
    [[ -n "$url" ]] || { warn "не удалось узнать последний релиз Proton Wineland"; return 1; }
    name=$(basename "$url" .tar.xz)
    dir="$COMPAT_DIR/$name"
    date +%s > "$DATA/.wineland-check"

    if [[ ! -x "$dir/proton" ]]; then
        msg "Качаю Proton Wineland: $name"
        tmp=$(mktemp -d)
        if ! curl -fL --retry 3 -# -o "$tmp/$name.tar.xz" "$url" ||
           ! curl -fsSL --retry 3 -o "$tmp/$name.sha512sum" "${url%.tar.xz}.sha512sum" ||
           ! (cd "$tmp" && sha512sum -c "$name.sha512sum" >/dev/null); then
            rm -rf "$tmp"; warn "не удалось скачать или проверить $name"; return 1
        fi
        mkdir -p "$COMPAT_DIR"
        tar xf "$tmp/$name.tar.xz" -C "$COMPAT_DIR"; rm -rf "$tmp"
        [[ -x "$dir/proton" ]] || { warn "в архиве нет $name/proton"; return 1; }
    fi

    # держим текущий и новый: на текущем может идти игра, остальные удаляем
    for d in "$COMPAT_DIR"/proton-wineland*; do
        [[ "$d" == "$dir" || "$d" == "${PROTONPATH_WAYLAND:-}" ]] || rm -rf "$d"
    done
    set_config PROTONPATH_WAYLAND "$dir"
    PROTONPATH_WAYLAND="$dir"
    msg "Proton Wineland: $name"
}

# перед запуском в Wayland-режиме: нет Wineland — ставим сразу, есть — раз в сутки
# проверяем обновление в фоне, новая версия подхватится со следующего запуска
check_wineland() {
    [[ "${WINELAND_UPDATE:-1}" == 1 && "$RUNNER" == umu ]] && use_wayland || return 0
    if [[ ! -x "${PROTONPATH_WAYLAND:-}/proton" ]]; then
        update_wineland || warn "Wayland-режим пойдёт на $PROTONPATH"
        return 0
    fi
    local last; last=$(cat "$DATA/.wineland-check" 2>/dev/null || echo 0)
    (( $(date +%s) - last > 86400 )) && { update_wineland >/dev/null 2>&1 & }
    return 0
}

use_wayland() {
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 1
    case "${WAYLAND:-auto}" in
        1) return 0 ;;
        auto) [[ "${XDG_SESSION_TYPE:-wayland}" == wayland ]] ;;
        *) return 1 ;;
    esac
}

run_wine() {
    export WINEPREFIX LC_ALL="$LOCALE" LANG="$LOCALE"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
    local e; for e in $EXTRA_ENV; do export "${e?}"; done
    mkdir -p "$WINEPREFIX"
    if [[ "$RUNNER" == umu ]]; then
        command -v umu-run >/dev/null || die "нет umu-run (pacman -S umu-launcher)"
        local proton="$PROTONPATH"
        if use_wayland; then
            export PROTON_ENABLE_WAYLAND=1
            [[ -x "${PROTONPATH_WAYLAND:-}/proton" ]] && proton="$PROTONPATH_WAYLAND"
        fi
        GAMEID="${GAMEID:-umu-arizona}" PROTONPATH="$proton" STORE=none umu-run "$@"
    else
        command -v wine >/dev/null || die "нет wine (лучше wine-staging)"
        wine "$@"
    fi
}

run_winetricks() {
    if [[ "$RUNNER" == umu ]]; then run_wine winetricks "$@"
    else WINEPREFIX="$WINEPREFIX" winetricks "$@"; fi
}

# ---------- установка ----------

# 7z (p7zip, Arch 7zip) или 7zz (пакет 7zip в Debian/Ubuntu)
sevenzip() { command -v 7z || command -v 7zz; }

check_deps() {
    local miss=() d
    for d in zenity curl; do command -v "$d" >/dev/null || miss+=("$d"); done
    sevenzip >/dev/null || miss+=(7zip)
    if [[ "$RUNNER" == umu ]]; then command -v umu-run >/dev/null || miss+=(umu-launcher)
    else command -v wine >/dev/null || miss+=(wine-staging); fi
    command -v winetricks >/dev/null || miss+=(winetricks)
    ((${#miss[@]} == 0)) || die "не хватает: ${miss[*]}  (команды для разных дистрибутивов в README)"
    locale -a 2>/dev/null | grep -qi '^ru_RU.utf' ||
        warn "нет локали ru_RU.UTF-8: раскомментируй её в /etc/locale.gen и запусти sudo locale-gen"
}

download_installer() { # печатает путь к скачанному установщику
    local out="$DATA/cache/Arizona Launcher.exe" url size
    mkdir -p "$DATA/cache"
    for url in "${MIRRORS[@]}"; do
        size=$(curl -sIL -A "$UA" "$url" | tr -d '\r' | awk 'tolower($1)=="content-length:" { s=$2 } END { print s }')
        [[ -n "$size" ]] || continue
        if [[ -f "$out" && "$(stat -c%s "$out")" == "$size" ]]; then
            msg "Установщик уже скачан: $out" >&2; echo "$out"; return
        fi
        msg "Качаю установщик ($((size / 1048576)) МБ): $url" >&2
        if curl -fL -A "$UA" -C - --retry 3 -# -o "$out" "$url" >&2 &&
           [[ "$(stat -c%s "$out")" == "$size" ]]; then
            echo "$out"; return
        fi
        warn "не скачалось с $url"; rm -f "$out"
    done
    return 1
}

pick_installer() {
    local f="${1:-}"
    [[ -n "$f" ]] || f=$(download_installer) || f=""
    if [[ -z "$f" ]]; then
        warn "зеркала недоступны, выбери установщик вручную"
        f=$(zenity --file-selection --title="Выбери установщик Arizona Games Launcher (.exe)" \
            --file-filter="*.exe *.EXE" 2>/dev/null) || die "установщик не выбран"
    fi
    [[ -f "$f" ]] || die "файла нет: $f"
    realpath "$f"
}

# ImGui-меню игры (AZVoice, azrtc, конфигуратор) грузят Segoe UI прямо из
# C:\Windows\Fonts. Его нет ни в Wine, ни в corefonts, подкладываем Noto Sans
install_fonts() {
    local fonts="$WINEPREFIX/drive_c/windows/Fonts" reg bold
    reg=$(fc-match -f '%{file}' 'Noto Sans:style=Regular' 2>/dev/null || true)
    bold=$(fc-match -f '%{file}' 'Noto Sans:style=Bold' 2>/dev/null || true)
    [[ "$reg" == *.ttf && "$bold" == *.ttf ]] || { warn "нет Noto Sans (pacman -S noto-fonts), Segoe UI не подменён"; return 0; }
    mkdir -p "$fonts"
    cp -n "$reg"  "$fonts/segoeui.ttf"
    cp -n "$bold" "$fonts/segoeuib.ttf"
    cp -n "$bold" "$fonts/seguisb.ttf"
}

# ---------- ArzMarket ----------

game_dir() { # папка Arizona RP внутри лаунчера, появляется после скачивания игры
    local d; d="$(dirname "$LAUNCHER_EXE")/bin/arizona"
    [[ -n "$LAUNCHER_EXE" && -f "$d/gta_sa.exe" ]] && echo "$d"
}

install_arzmarket() {
    local game tmp backup f
    game=$(game_dir) || die "игра ещё не скачана: запусти arizona и скачай Arizona RP"
    # MoonLoader по умолчанию не стоит, его ставит лаунчер Аризоны
    [[ -f "$game/MoonLoader.asi" ]] || die "нет MoonLoader: поставь его в лаунчере Аризоны (раздел «Моды»), потом повтори"
    tmp=$(mktemp -d)
    msg "Качаю ArzMarket"
    curl -fL --retry 3 -# -o "$tmp/cache.zip" "$ARZMARKET_URL" || { rm -rf "$tmp"; die "не скачался ArzMarket"; }
    "$(sevenzip)" x -y -o"$tmp/files" "$tmp/cache.zip" >/dev/null || { rm -rf "$tmp"; die "не распаковался ArzMarket"; }

    # файлы игры, которые архив заменит, сохраняем, чтобы --arzmarket-remove мог их вернуть
    backup="$DATA/arzmarket-backup"
    mkdir -p "$backup"
    while IFS= read -r -d '' f; do
        f=${f#"$tmp/files/"}
        if [[ -f "$game/$f" && ! -e "$backup/$f" ]] && ! cmp -s "$tmp/files/$f" "$game/$f"; then
            mkdir -p "$backup/$(dirname "$f")"; cp -p "$game/$f" "$backup/$f"
        fi
    done < <(find "$tmp/files" -type f -print0)
    (cd "$tmp/files" && find . -type f) > "$backup/files.txt"

    cp -r "$tmp/files/." "$game/"
    rm -rf "$tmp"
    msg "ArzMarket установлен в $game/moonloader"
}

remove_arzmarket() {
    local game backup="$DATA/arzmarket-backup"
    game=$(game_dir) || die "игра не найдена"
    rm -rf "$game/moonloader/ArzMarket" "$game"/moonloader/\#ArzMarket*.lua "$game/moonloader/ArzMarket_Loader.lua"
    [[ -d "$backup" ]] && cp -r "$backup/." "$game/" && rm -f "$game/files.txt" && rm -rf "$backup"
    msg "ArzMarket удалён"
}

find_launcher_exe() {
    local c="$WINEPREFIX/drive_c"
    find "$c/users" "$c/Program Files" "$c/Program Files (x86)" "$c/Games" -maxdepth 6 \
        -iname '*arizona*.exe' ! -iname '*unins*' ! -iname '*setup*' ! -iname '*install*' \
        ! -iname '*update*' 2>/dev/null | awk '{ print length, $0 }' | sort -n | cut -d' ' -f2- | head -n1 || true
}

extract_icon() {
    local exe="$1" tmp; tmp=$(mktemp -d)
    if "$(sevenzip)" x -y -o"$tmp" "$exe" '.rsrc/ICON/*' '.rsrc/*/ICON/*' >/dev/null 2>&1; then
        # самый большой ресурс иконки обычно 256x256 PNG
        local best; best=$(find "$tmp" -type f -printf '%s %p\n' | sort -n | tail -n1 | cut -d' ' -f2-)
        if [[ -n "$best" ]] && file -b "$best" | grep -q PNG; then cp "$best" "$ICON"; fi
    fi
    rm -rf "$tmp"
}

write_desktop() {
    local icon="applications-games"; [[ -f "$ICON" ]] && icon="$ICON"
    mkdir -p "$(dirname "$DESKTOP")"
    cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Arizona Games Launcher
Comment=Arizona RP (SA:MP) и Rodina RP (CRMP) через Proton
Exec=$BIN
Icon=$icon
Terminal=false
Categories=Game;
StartupWMClass=arizona games launcher.exe
EOF
    update-desktop-database "$(dirname "$DESKTOP")" 2>/dev/null || true
}

install_self() {
    mkdir -p "$(dirname "$BIN")"
    if [[ "$(realpath "$0")" != "$(realpath "$BIN" 2>/dev/null || true)" ]]; then
        install -m755 "$0" "$BIN"
    fi
    [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || warn "~/.local/bin нет в PATH, добавь: fish_add_path ~/.local/bin"
}

do_install() {
    load_config; check_deps
    local inst; inst=$(pick_installer "${1:-}")
    install_self

    msg "Создаю префикс: $WINEPREFIX"
    run_wine wineboot -u >/dev/null 2>&1 || true

    msg "Ставлю шрифты и рантаймы (corefonts, vcrun2022), это займёт несколько минут"
    run_winetricks -q corefonts vcrun2022 || warn "winetricks завершился с ошибкой, продолжаю"
    install_fonts
    check_wineland

    # electron-builder NSIS: /S ставит молча в %LOCALAPPDATA%\Programs
    msg "Тихо ставлю лаунчер"
    # в конце установщик пытается сам открыть лаунчер и ругается на ShellExecuteEx, это не страшно
    run_wine "$inst" /S || true
    [[ "$RUNNER" == umu ]] || wineserver -w 2>/dev/null || true

    local exe; exe=$(find_launcher_exe)
    if [[ -z "$exe" ]]; then
        warn "Не нашёл exe лаунчера. Укажи его вручную: arizona --set-exe /путь/к/лаунчеру.exe"
    else
        set_config LAUNCHER_EXE "$exe"; msg "Лаунчер: $exe"
        extract_icon "$exe"
    fi
    write_desktop
    msg "Готово. Запуск: arizona (или из меню приложений)"
}

# ---------- команды ----------

do_run() {
    load_config
    [[ -n "$LAUNCHER_EXE" && -f "$LAUNCHER_EXE" ]] || LAUNCHER_EXE=$(find_launcher_exe)
    [[ -n "$LAUNCHER_EXE" ]] || die "лаунчер не установлен: arizona-winello.sh install"
    check_wineland
    cd "$(dirname "$LAUNCHER_EXE")"
    # игра наследует окружение лаунчера, поэтому настройки DXVK задаём здесь
    export DXVK_CONFIG="d3d9.maxFrameLatency = 1; d3d9.maxFrameRate = ${FPS_LIMIT:-0}"
    if [[ "${MANGOHUD:-0}" == 1 ]]; then
        export MANGOHUD=1
        export MANGOHUD_CONFIG="${MANGOHUD_CONFIG:-fps,frametime,frame_timing,cpu_stats,core_load,cpu_mhz,gpu_stats,gpu_core_clock,vram,ram}"
    fi
    local wrap=()
    if [[ "${GAMEMODE:-0}" == 1 ]] && command -v gamemoderun >/dev/null; then wrap=(gamemoderun); fi

    # Лаунчер помечает скачанное «Mark of the Web». В Windows это скрытый поток
    # файла, а Wine создаёт отдельные файлы «имя:Zone.Identifier», и игра пытается
    # грузить их как шрифты. Чистим при старте и пока лаунчер качает обновления
    local dir; dir=$(dirname "$LAUNCHER_EXE")
    clean_zone() { find "$dir" -name '*:Zone.Identifier' -delete 2>/dev/null || true; }

    # Пока идёт игра, Electron-лаунчер продолжает рисовать интерфейс и дёргать
    # tasklist.exe, а это до половины слабого CPU. SCHED_IDLE отдаёт ему только
    # простаивающее процессорное время. Дочерние процессы наследуют политику
    idle_launcher() {
        [[ "${IDLE_LAUNCHER:-1}" == 1 ]] && pgrep -x gta_sa.exe >/dev/null || return 0
        local p
        for p in $(pgrep -f 'Arizona Games Launcher\.exe'); do
            chrt -p "$p" 2>/dev/null | grep -q SCHED_IDLE || chrt -a -i -p 0 "$p" 2>/dev/null || true
        done
    }

    clean_zone
    ( while sleep 3; do clean_zone; idle_launcher; done ) &
    local cleaner=$!
    trap 'kill $cleaner 2>/dev/null' EXIT

    # В Wayland-драйвере Wine окно, которое рисует отдельный GPU-процесс Electron,
    # остаётся пустым. Рисуем в основном процессе лаунчера
    local extra=()
    use_wayland && extra+=(--in-process-gpu)

    # shellcheck disable=SC2086
    "${wrap[@]}" "$0" --wine "$LAUNCHER_EXE" $LAUNCHER_ARGS "${extra[@]}" "$@"
}

do_info() {
    load_config
    cat <<EOF
Конфиг:    $CFG
Префикс:   $WINEPREFIX
Раннер:    $RUNNER  (Proton: $PROTONPATH)
Wayland:   $WAYLAND, сейчас $(use_wayland && echo "да (${PROTONPATH_WAYLAND:-$PROTONPATH})" || echo "нет, XWayland/X11")
Лаунчер:   ${LAUNCHER_EXE:-не найден}
Аргументы: $LAUNCHER_ARGS
Локаль:    $LOCALE
EOF
}

do_kill() {
    load_config
    if [[ "${1:-}" == 9 ]]; then
        pkill -9 -f "$WINEPREFIX" 2>/dev/null || true
        pkill -9 -fi 'arizona.*\.exe|gta_sa\.exe|cef_proc' 2>/dev/null || true
    else
        local ws=wineserver
        [[ "$RUNNER" == umu && -x "$PROTONPATH/files/bin/wineserver" ]] && ws="$PROTONPATH/files/bin/wineserver"
        WINEPREFIX="$WINEPREFIX" "$ws" -k 2>/dev/null || true
    fi
}

do_fixprefix() {
    load_config
    zenity --question --text="Удалить префикс\n$WINEPREFIX\nи поставить лаунчер заново?\n(Игра внутри префикса тоже удалится)" 2>/dev/null || exit 0
    do_kill 9; rm -rf "$WINEPREFIX"; set_config LAUNCHER_EXE ""
    do_install "${1:-}"
}

do_remove() {
    load_config
    zenity --question --text="Удалить arizona-winello вместе с префиксом и игрой?" 2>/dev/null || exit 0
    do_kill 9
    rm -rf "$DATA" "$DESKTOP" "$BIN"
    msg "Удалено"
}

usage() {
    cat <<EOF
arizona-winello: Arizona Games Launcher на Linux

Установка:
  ./arizona-winello.sh install [установщик.exe]   (без аргумента скачает сам)

После установки:
  arizona                 запустить лаунчер
  arizona --wine <args>   выполнить wine в префиксе (например: --wine cmd)
  arizona --winecfg       winecfg
  arizona --winetricks .. winetricks в префиксе
  arizona --regedit       regedit
  arizona --set-exe PATH  указать exe лаунчера вручную
  arizona --fixfonts      подложить замену Segoe UI для меню игры
  arizona --arzmarket     поставить ArzMarket (MoonLoader-скрипт для рынка)
  arizona --arzmarket-remove  удалить ArzMarket и вернуть заменённые файлы
  arizona --update-wineland  проверить и поставить свежий Proton Wineland
  arizona --info          показать настройки
  arizona --edit-config   открыть конфиг
  arizona --kill / --kill9  закрыть / убить всё в префиксе
  arizona --fixprefix     пересоздать префикс и поставить заново
  arizona --remove        удалить всё
EOF
}

case "${1:-}" in
    install|--install) shift; do_install "$@" ;;
    "")                do_run ;;
    --wine)            shift; load_config; run_wine "$@" ;;
    --winecfg)         load_config; run_wine winecfg ;;
    --regedit)         load_config; run_wine regedit ;;
    --winetricks)      shift; load_config; run_winetricks "$@" ;;
    --set-exe)         load_config; [[ -f "${2:-}" ]] || die "нет файла: ${2:-}"
                       set_config LAUNCHER_EXE "$(realpath "$2")"; extract_icon "$2"; write_desktop ;;
    --fixfonts)        load_config; install_fonts; msg "Шрифты на месте" ;;
    --arzmarket)       load_config; [[ -n "$LAUNCHER_EXE" ]] || LAUNCHER_EXE=$(find_launcher_exe)
                       install_arzmarket ;;
    --arzmarket-remove) load_config; [[ -n "$LAUNCHER_EXE" ]] || LAUNCHER_EXE=$(find_launcher_exe); remove_arzmarket ;;
    --update-wineland) load_config; update_wineland ;;
    --info)            do_info ;;
    --edit-config)     load_config; "${EDITOR:-xdg-open}" "$CFG" ;;
    --kill)            do_kill ;;
    --kill9)           do_kill 9 ;;
    --fixprefix)       shift; do_fixprefix "$@" ;;
    --remove)          do_remove ;;
    -h|--help|help)    usage ;;
    --)                shift; do_run "$@" ;;
    *)                 do_run "$@" ;;
esac
