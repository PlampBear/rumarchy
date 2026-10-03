#!/usr/bin/env bash
# rumarchy — установка русской локали и раскладки на Omarchy (Arch + Hyprland).
#
# Что делает:
#   1. Включает ru_RU.UTF-8 (и en_US.UTF-8 как запасной) в /etc/locale.gen, генерирует локали
#   2. Ставит системную локаль LANG=ru_RU.UTF-8
#   3. Настраивает раскладки us,ru с переключением Ctrl+Shift
#   4. Кладёт пользовательское окружение (LANG/LANGUAGE) для GUI-приложений
#   5. Вставляет блок input в ~/.config/hypr/input.lua, сохраняя остальные настройки
#
# Использование:
#   ./install.sh              — обычная установка
#   ./install.sh --check      — только показать текущее состояние, ничего не менять
#   ./install.sh --uninstall  — откатить локаль на en_US.UTF-8 (Hyprland-блок остаётся)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$HERE/files"

KB_LAYOUT="${RU_KB_LAYOUT:-us,ru}"
KB_OPTIONS="${RU_KB_OPTIONS:-grp:ctrl_shift_toggle,terminate:ctrl_alt_bksp}"
SWITCH_KEY="${RU_SWITCH_KEY:-Ctrl+Shift}"

die() { printf 'ошибка: %s\n' "$1" >&2; exit 1; }

# --- Проверка окружения ---------------------------------------------------

check_env() {
  command -v localectl >/dev/null || die "localectl не найден — это не systemd-система"
  if [ ! -d /usr/share/omarchy ]; then
    printf 'предупреждение: /usr/share/omarchy не найден, скрипт рассчитан на Omarchy.\n' >&2
    printf '             на чистом Arch с Hyprland он тоже работоспособен.\n' >&2
  fi
}

show_state() {
  echo "=== localectl ==="
  localectl status 2>/dev/null | sed 's/^/  /' || true
  echo "=== сгенерированные локали ==="
  locale -a 2>/dev/null | grep -E '^(ru_RU|en_US)' | sed 's/^/  /' || echo "  (пусто)"
  echo "=== пользовательское окружение ==="
  if [ -f "$HOME/.config/environment.d/10-locale.conf" ]; then
    sed 's/^/  /' "$HOME/.config/environment.d/10-locale.conf"
  else
    echo "  (нет ~/.config/environment.d/10-locale.conf)"
  fi
  echo "=== hypr/input.lua ==="
  if [ -f "$HOME/.config/hypr/input.lua" ]; then
    grep -nE 'kb_layout|kb_options' "$HOME/.config/hypr/input.lua" | sed 's/^/  /' || echo "  (раскладка не задана)"
  else
    echo "  (нет ~/.config/hypr/input.lua)"
  fi
}

# --- Привилегированная часть ---------------------------------------------
# Вынесена в отдельный скрипт, потому что sudo/pkexec не должен мешать
# пользовательским правкам и выполняться одним вызовом.

privileged() {
  set -e
  cp -a /etc/locale.gen "/etc/locale.gen.bak.$(date +%Y%m%d-%H%M%S)"
  sed -i 's/^#\s*ru_RU\.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
  sed -i 's/^#\s*en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen

  localectl set-locale LANG=ru_RU.UTF-8

  # Порядок важен: set-x11-keymap сбрасывает VC Keymap на первый layout,
  # поэтому русская раскладка не должна осесть в консоли и парольном вводе.
  localectl set-x11-keymap "$KB_LAYOUT" pc105 '' "$KB_OPTIONS"
  localectl set-keymap --no-convert us
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    privileged
  elif command -v pkexec >/dev/null; then
    # pkexec — для запуска без интерактивного терминала (CI, агент, демон).
    # В обычном терминале предпочтительнее sudo.
    tmp="$(mktemp)"
    cat >"$tmp" <<EOF
#!/bin/bash
KB_LAYOUT='$KB_LAYOUT'
KB_OPTIONS='$KB_OPTIONS'
$(declare -f privileged)
privileged
EOF
    chmod 755 "$tmp"
    pkexec /bin/bash "$tmp"
    rm -f "$tmp"
  else
    die "нужен root: запустите через sudo"
  fi
}

uninstall() {
  echo "Откат системной локали на en_US.UTF-8…"
  if [ "$(id -u)" -eq 0 ]; then
    localectl set-locale LANG=en_US.UTF-8
    localectl set-x11-keymap us pc105+inet '' 'terminate:ctrl_alt_bksp'
  else
    sudo localectl set-locale LANG=en_US.UTF-8
    sudo localectl set-x11-keymap us pc105+inet '' 'terminate:ctrl_alt_bksp'
  fi
  echo "Готово. Раскладку Hyprland и файл environment.d нужно убрать вручную:"
  echo "  rm ~/.config/environment.d/10-locale.conf"
  echo "  удалите блок input из ~/.config/hypr/input.lua"
}

# --- Пользовательская часть ----------------------------------------------

user_env() {
  mkdir -p "$HOME/.config/environment.d"
  cat >"$HOME/.config/environment.d/10-locale.conf" <<EOF
LANG=ru_RU.UTF-8
LANGUAGE=ru_RU:ru
EOF
}

hypr_input() {
  local f="$HOME/.config/hypr/input.lua"
  [ -f "$f" ] || { echo "  пропуск: $f не найден"; return 0; }

  if grep -q 'kb_layout' "$f" && grep -qvE '^\s*--\s*kb_layout' <<<"$(grep 'kb_layout' "$f")"; then
    echo "  в $f уже есть активный kb_layout — оставляю как есть"
    return 0
  fi

  cp -a "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"

  local block
  block=$(cat <<EOF
-- Keyboard layout and options.
-- See https://wiki.hypr.land/Configuring/Basics/Variables/#input
hl.config({
  input = {
    -- Russian + English layouts. Switch with $SWITCH_KEY.
    kb_layout = "$KB_LAYOUT",
    kb_options = "$KB_OPTIONS",
  },
})

EOF
)

  # Вставляем блок сразу после строки-ссылки на документацию input.
  # Так он оказывается перед закомментированным стоковым примером.
  awk -v block="$block" '
    { print }
    /wiki\.hypr\.land\/Configuring\/Basics\/Variables\/#input/ && !done { print block; done=1 }
  ' "$f" >"$f.new" && mv "$f.new" "$f"
  echo "  блок input добавлен в $f (бэкап: $f.bak.*)"
}

import_env() {
  systemctl --user import-environment LANG LANGUAGE 2>/dev/null || true
  dbus-update-activation-environment --systemd LANG LANGUAGE 2>/dev/null || true
}

# --- main -----------------------------------------------------------------

case "${1:-}" in
  --check)
    check_env; show_state; exit 0 ;;
  --uninstall)
    uninstall; exit 0 ;;
  --help|-h)
    sed -n '2,20p' "$0"; exit 0 ;;
  "") ;;
  *) die "неизвестный аргумент: $1 (см. --help)" ;;
esac

check_env
echo "==> системная часть (нужен root)"
run_privileged
echo "==> пользовательская часть"
user_env
echo "  создан ~/.config/environment.d/10-locale.conf"
hypr_input
import_env

echo
show_state
cat <<EOF

Готово. Русская локаль и раскладка $KB_LAYOUT настроены.

Что дальше:
  * Переключение раскладки — $SWITCH_KEY
  * Консольная раскладка (пароли в TTY) осталась us — русская туда не попадает
  * Уже запущенные GUI-приложения читают локаль при старте:
    выполните выход из сессии и повторный вход, либо перезагрузите систему
  * Проверить после перезагрузки:
      hyprctl getoption input:kb_layout
      hyprctl configerrors
EOF