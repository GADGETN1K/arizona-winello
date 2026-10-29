# arizona-winello

Установка и запуск **Arizona Games Launcher** на Linux: в нём **Arizona RP** (GTA SA:MP)
и **Rodina RP** (CRMP). Работает через
[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) и GE-Proton.
По мотивам [osu-winello](https://github.com/NelloKudo/osu-winello).

## Что делает

- скачивает официальный установщик лаунчера (есть два зеркала, скачивание продолжается после обрыва) и ставит его без окон (`/S`);
- создаёт отдельный префикс, ставит `corefonts` и `vcrun2022`;
- подменяет Segoe UI на Noto Sans: меню игры (AZVoice, azrtc, конфигуратор) грузят Segoe UI напрямую из `C:\Windows\Fonts`;
- удаляет файлы `*:Zone.Identifier`, которые Wine создаёт вместо скрытых потоков NTFS (из-за них игра падает на загрузке шрифтов);
- пока идёт игра, отдаёт лаунчеру только свободное процессорное время (`SCHED_IDLE`);
- в Wayland-сессии сам переключается на нативный Wayland-драйвер Wine и
  [Proton Wineland](https://github.com/nanomatters/proton-salkim): скачивает последний релиз с GitHub
  под твой уровень x86-64 (v3 или обычный) и раз в сутки проверяет обновления. В X11 работает через GE-Proton;
- запускает через Feral GameMode, по желанию с MangoHud и лимитом FPS через DXVK;
- создаёт ярлык в меню с иконкой из exe;
- по флагу `--arzmarket` ставит [ArzMarket](https://github.com/FREYM1337/forumnick) (MoonLoader-скрипт
  для рынка Arizona RP). Сначала поставь MoonLoader в лаунчере Аризоны (раздел «Моды»). Это сторонний
  скрипт с закрытым кодом, который сам обновляется из интернета, так что ставишь на свой риск.

## Зависимости

Нужны: `umu-launcher`, `winetricks`, `zenity`, `7z` или `7zz`, `curl` и шрифт Noto Sans.
По желанию: `gamemode` и `mangohud`. Сам GE-Proton ставить не нужно: если его нет в системе,
umu скачает свежий сам.

**Arch / CachyOS / Manjaro**

```sh
sudo pacman -S umu-launcher winetricks zenity 7zip curl noto-fonts gamemode mangohud
```

**Debian 12–13 / Ubuntu 24.04+ / Mint**

```sh
sudo apt install winetricks zenity 7zip curl fonts-noto-core gamemode mangohud
```

umu-launcher в репозиториях Debian и Ubuntu нет. Возьми два `.deb` под свою систему
(`umu-launcher_*_all_<система>.deb` и `python3-umu-launcher_*_amd64_<система>.deb`)
со страницы [релизов umu](https://github.com/Open-Wine-Components/umu-launcher/releases)
и поставь их: `sudo apt install ./umu-launcher_*.deb ./python3-umu-launcher_*.deb`.

**Fedora 43–44**

```sh
sudo dnf install winetricks zenity p7zip p7zip-plugins curl google-noto-sans-fonts gamemode mangohud
sudo dnf install https://github.com/Open-Wine-Components/umu-launcher/releases/latest/download/umu-launcher-<версия>.fc<версия Fedora>.x86_64.rpm
```

Точное имя rpm посмотри на странице [релизов umu](https://github.com/Open-Wine-Components/umu-launcher/releases).
В Nobara umu уже есть в репозитории: `sudo dnf install umu-launcher`.

**openSUSE Tumbleweed**

```sh
sudo zypper install winetricks zenity 7zip curl google-noto-sans-fonts gamemode mangohud
```

**Void Linux**

```sh
sudo xbps-install winetricks zenity 7zip curl noto-fonts-ttf gamemode MangoHud
```

Для openSUSE, Void и всех остальных дистрибутивов umu ставится из универсального zipapp:

```sh
curl -LO https://github.com/Open-Wine-Components/umu-launcher/releases/latest/download/umu-launcher-<версия>-zipapp.tar
tar xf umu-launcher-*-zipapp.tar
install -Dm755 umu/umu-run ~/.local/bin/umu-run
```

**NixOS**: `pkgs.umu-launcher` в nixpkgs начиная с 25.05.

Для русских шрифтов нужна локаль `ru_RU.UTF-8`: раскомментируй её в `/etc/locale.gen`
и запусти `sudo locale-gen` (в Debian и Ubuntu: `sudo dpkg-reconfigure locales`).

## Установка

```sh
git clone https://github.com/GADGETN1K/arizona-winello
cd arizona-winello
./arizona-winello.sh install                  # скачает установщик сам
./arizona-winello.sh install ~/Загрузки/x.exe  # или с готовым установщиком
```

Скрипт копирует себя в `~/.local/bin/arizona`.

## Использование

```
arizona                 запустить лаунчер
arizona --wine <args>   выполнить wine в префиксе
arizona --winecfg       winecfg
arizona --winetricks .. winetricks в префиксе
arizona --regedit       regedit
arizona --set-exe PATH  указать exe лаунчера вручную
arizona --fixfonts      подложить замену Segoe UI
arizona --arzmarket     поставить ArzMarket
arizona --arzmarket-remove  удалить ArzMarket и вернуть заменённые файлы
arizona --update-wineland  проверить и поставить свежий Proton Wineland
arizona --info          показать настройки
arizona --edit-config   открыть конфиг
arizona --kill / --kill9
arizona --fixprefix     пересоздать префикс
arizona --remove        удалить всё
```

## Настройки

`~/.local/share/arizona-winello/config.cfg` (`arizona --edit-config`):

| Параметр | По умолчанию | Что делает |
|---|---|---|
| `RUNNER` | `umu` | `umu` (Proton) или `wine` (системный) |
| `PROTONPATH` | системный GE-Proton или `GE-Proton` | какой Proton использовать |
| `LAUNCHER_ARGS` | `--no-sandbox` | аргументы Electron-лаунчера |
| `LOCALE` | `ru_RU.UTF-8` | локаль |
| `GAMEMODE` | `1` | запуск через `gamemoderun` |
| `MANGOHUD` | `0` | оверлей MangoHud |
| `FPS_LIMIT` | `0` | лимит FPS через DXVK, `0` = без лимита |
| `IDLE_LAUNCHER` | `1` | `SCHED_IDLE` для лаунчера, пока идёт игра |
| `WAYLAND` | `auto` | Wayland-драйвер Wine: `auto` — в Wayland-сессии, `1` — всегда, `0` — никогда |
| `PROTONPATH_WAYLAND` | Proton Wineland | какой Proton брать в Wayland-режиме |
| `WINELAND_UPDATE` | `1` | раз в сутки проверять новый релиз Wineland |
| `EXTRA_ENV` | | доп. переменные окружения |

Чтобы GameMode мог менять governor и частоты GPU, добавь себя в группу `gamemode`
(`sudo usermod -aG gamemode $USER`), а секцию `[gpu]` положи в `/etc/gamemode.ini`.

## Wayland

В Wayland-сессии (`WAYLAND="auto"`) лаунчер и игра идут через нативный Wayland-драйвер Wine,
а не через XWayland. На слабом железе это заметно быстрее: на A12-9800 было 7–30 FPS через
XWayland и около 70 через Wayland. Для этого скрипт сам ставит
[Proton Wineland](https://github.com/nanomatters/proton-salkim) в
`~/.local/share/Steam/compatibilitytools.d/` и добавляет Electron-лаунчеру `--in-process-gpu`:
без него окно лаунчера в Wayland остаётся пустым.
