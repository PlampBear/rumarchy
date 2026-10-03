# rumarchy

Русская локаль и раскладка для [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland) — установочный скрипт вместо ручной настройки.

Раскладка `us,ru`, переключение — **Ctrl+Shift**, консольная раскладка остаётся `us`, чтобы русская не вставала в парольный ввод.

## Установка

```bash
git clone https://github.com/DIMONZAV/rumarchy.git
cd rumarchy
./install.sh
```

Скрипт спросит пароль root (через `pkexec`). Дальше:

```bash
./install.sh --check      # посмотреть текущее состояние, ничего не меняя
./install.sh --uninstall  # откатить системную локаль на en_US.UTF-8
```

**После установки перезайдите в сессию** — уже запущенные приложения читают локаль только при старте.

## Что делает

1. Включает `ru_RU.UTF-8` (и `en_US.UTF-8` как запасной) в `/etc/locale.gen`, генерирует локали
2. Ставит `LANG=ru_RU.UTF-8` системно
3. Настраивает X11/раскладки `us,ru` с переключением Ctrl+Shift
4. Кладёт `LANG` и `LANGUAGE` в `~/.config/environment.d/10-locale.conf` для GUI-приложений
5. Вставляет блок `input` в `~/.config/hypr/input.lua`, не трогая остальные настройки

Перед каждой правкой создаётся резервная копия с меткой времени.

## Важная деталь: порядок вызовов

```bash
localectl set-x11-keymap us,ru pc105 '' grp:ctrl_shift_toggle,...
localectl set-keymap --no-convert us
```

`set-x11-keymap` сбрасывает VC Keymap на первый layout, из-за чего русская раскладка
попадает в консоль и парольный ввод. Отдельный `set-keymap --no-convert us` после него
возвращает консоль в `us`. Если поменять порядок — пароль в TTY начнёт вводиться
кириллицей.

## Настройка под себя

Переменные окружения читаются при запуске:

```bash
RU_KB_LAYOUT="us,ru"                  RU_KB_LAYOUT="de,us,ru" ./install.sh
RU_KB_OPTIONS="grp:alt_shift_toggle"  RU_SWITCH_KEY="Alt+Shift"     ./install.sh
```

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `RU_KB_LAYOUT` | `us,ru` | список раскладок для X11 и Hyprland |
| `RU_KB_OPTIONS` | `grp:ctrl_shift_toggle,terminate:ctrl_alt_bksp` | переключение групп и аварийное завершение |
| `RU_SWITCH_KEY` | `Ctrl+Shift` | только текст в комментарии и подсказке |

## Проверка после перезагрузки

```bash
localectl status
locale -a | grep -E '^(ru_RU|en_US)'
hyprctl getoption input:kb_layout
hyprctl configerrors
```

Ожидаемый вывод `localectl status`:

```text
System Locale: LANG=ru_RU.UTF-8
    VC Keymap: us
   X11 Layout: us,ru
    X11 Model: pc105
  X11 Options: grp:ctrl_shift_toggle,terminate:ctrl_alt_bksp
```

## Что осталось за рамками

- Перевод меню Omarchy — не входит, локаль влияет на приложения с поддержкой i18n
- Значки и темы — не трогаются
- Telegram и другие клиенты подхватывают локаль после рестарта

## Требования

Arch-подобная система с systemd и `localectl`. Проверено на Omarchy 4.0.4 (Arch, Hyprland).

Скрипт также работает на чистом Arch с Hyprland, но там нужно создать
`~/.config/hypr/input.lua` и `~/.config/hypr/environment.conf` вручную — сам Hyprland
не подхватит `.lua`-конфиги без `source` в основном конфиге.

## Лицензия

MIT