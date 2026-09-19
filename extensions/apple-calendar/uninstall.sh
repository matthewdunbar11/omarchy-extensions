#!/bin/bash
# Uninstall apple-calendar. Removes code; keeps credentials + cache (see --purge).
set -euo pipefail

PLUGIN_ID="omx.apple-calendar"

systemctl --user disable --now omx-apple-calendar-sync.timer 2>/dev/null || true

rm -rf "$HOME/.config/omarchy/plugins/$PLUGIN_ID"
rm -f "$HOME/.config/systemd/user/omx-apple-calendar-sync.service" \
  "$HOME/.config/systemd/user/omx-apple-calendar-sync.timer" \
  "$HOME/.local/bin/apple-cal-sync"

if [[ ${1:-} == "--purge" ]]; then
  rm -rf "$HOME/.config/apple-calendar" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/omx/apple-calendar"
  systemctl --user daemon-reload 2>/dev/null || true
  echo "apple-calendar uninstalled + data purged."
else
  systemctl --user daemon-reload 2>/dev/null || true
  echo "apple-calendar uninstalled (credentials + cache kept; --purge removes them)."
  echo "If the bar still references omx.apple-calendar, point it back at omarchy.clock in shell.json"
  echo "(a *.bak.* backup was kept next to shell.json at install time)."
fi
