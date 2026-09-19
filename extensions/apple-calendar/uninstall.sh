#!/bin/bash
# Uninstall apple-calendar. Asks about purging credentials + cache on a TTY
# (--purge/--keep-data override; non-interactive keeps data).
set -euo pipefail

PLUGIN_ID="omx.apple-calendar"

PURGE=""
for a in "$@"; do
  case $a in
    --purge) PURGE=yes ;;
    --keep-data) PURGE=no ;;
  esac
done
if [[ -z $PURGE ]]; then
  if [[ -t 0 ]]; then
    read -rp "Also delete credentials (~/.config/apple-calendar) + event cache? [y/N] " ans
    [[ $ans == [yY]* ]] && PURGE=yes || PURGE=no
  else
    PURGE=no
  fi
fi

systemctl --user disable --now omx-apple-calendar-sync.timer 2>/dev/null || true

rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
rm -f "$HOME/.config/systemd/user/omx-apple-calendar-sync.service" \
  "$HOME/.config/systemd/user/omx-apple-calendar-sync.timer" \
  "$HOME/.local/bin/apple-cal-sync"

if [[ $PURGE == yes ]]; then
  rm -rf "$HOME/.config/apple-calendar" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/omx/apple-calendar"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "apple-calendar uninstalled + data purged."
else
  systemctl --user daemon-reload 2>/dev/null || true
  echo "apple-calendar uninstalled (credentials + cache kept)."
  echo "If the bar still references omx.apple-calendar, point it back at omarchy.clock in shell.json"
  echo "(a *.bak.* backup was kept next to shell.json at install time)."
fi
