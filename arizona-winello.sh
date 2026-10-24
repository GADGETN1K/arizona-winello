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

# Пока запущена игра, давать лаунчеру только свободный CPU (1/0)
IDLE_LAUNCHER="1"

# ArzMarket (MoonLoader-скрипт для рынка Arizona RP): 1 = поставить, как только игра скачана
ARZMARKET="0"

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

run_wine() {
    export WINEPREFIX LC_ALL="$LOCALE" LANG="$LOCALE"
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
    local e; for e in $EXTRA_ENV; do export "${e?}"; done
    mkdir -p "$WINEPREFIX"
    if [[ "$RUNNER" == umu ]]; then
        command -v umu-run >/dev/null || die "нет umu-run (pacman -S umu-launcher)"
        GAMEID="${GAMEID:-umu-arizona}" PROTONPATH="$PROTONPATH" STORE=none umu-run "$@"
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

arzmarket_installed() { compgen -G "$1/moonloader/#ArzMarket*.lua" >/dev/null; }

install_arzmarket() {
    local game tmp backup f
    game=$(game_dir) || { warn "игра ещё не скачана: запусти arizona, скачай Arizona RP, ArzMarket встанет сам"; return 1; }
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
    set_config ARZMARKET "0"
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

    if zenity --question --title="ArzMarket" --text="Поставить ArzMarket?\n\nЭто сторонний MoonLoader-скрипт для рынка Arizona RP (github.com/FREYM1337/forumnick).\nКод закрытый и сам обновляется из интернета, использование на свой риск.\n\nВстанет после того, как лаунчер скачает игру." 2>/dev/null; then
        set_config ARZMARKET "1"
    fi

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
    if [[ "${ARZMARKET:-0}" == 1 ]] && game=$(game_dir) && ! arzmarket_installed "$game"; then
        install_arzmarket || true
    fi
    ( while sleep 3; do clean_zone; idle_launcher; done ) &
    local cleaner=$!
    trap 'kill $cleaner 2>/dev/null' EXIT

    # shellcheck disable=SC2086
    "${wrap[@]}" "$0" --wine "$LAUNCHER_EXE" $LAUNCHER_ARGS "$@"
}

do_info() {
    load_config
    cat <<EOF
Конфиг:    $CFG
Префикс:   $WINEPREFIX
Раннер:    $RUNNER  (Proton: $PROTONPATH)
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
                       install_arzmarket && set_config ARZMARKET "1" ;;
    --arzmarket-remove) load_config; [[ -n "$LAUNCHER_EXE" ]] || LAUNCHER_EXE=$(find_launcher_exe); remove_arzmarket ;;
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
