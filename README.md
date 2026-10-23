# arizona-winello

Установка и запуск **Arizona Games Launcher** (Arizona RP, GTA SA:MP) на Linux через
[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher) и GE-Proton.
По мотивам [osu-winello](https://github.com/NelloKudo/osu-winello).

## Что делает

- скачивает официальный установщик лаунчера (есть два зеркала, скачивание продолжается после обрыва) и ставит его без окон (`/S`);
- создаёт отдельный префикс, ставит `corefonts` и `vcrun2022`;
- подменяет Segoe UI на Noto Sans: меню игры (AZVoice, azrtc, конфигуратор) грузят Segoe UI напрямую из `C:\Windows\Fonts`;
- удаляет файлы `*:Zone.Identifier`, которые Wine создаёт вместо скрытых потоков NTFS (из-за них игра падает на загрузке шрифтов);
- пока идёт игра, отдаёт лаунчеру только свободное процессорное время (`SCHED_IDLE`);
- запускает через Feral GameMode, по желанию с MangoHud и лимитом FPS через DXVK;
- создаёт ярлык в меню с иконкой из exe.

## Зависимости

Arch / CachyOS:

```sh
sudo pacman -S umu-launcher winetricks zenity 7zip curl noto-fonts
# по желанию
sudo pacman -S gamemode mangohud
```

Для русских шрифтов нужна локаль `ru_RU.UTF-8` (в `/etc/locale.gen`, затем `sudo locale-gen`).

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
| `EXTRA_ENV` | | доп. переменные окружения |

Чтобы GameMode мог менять governor и частоты GPU, добавь себя в группу `gamemode`
(`sudo usermod -aG gamemode $USER`), а секцию `[gpu]` положи в `/etc/gamemode.ini`.
