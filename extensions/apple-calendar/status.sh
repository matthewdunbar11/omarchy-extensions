#!/bin/bash
# Report install state. Exit 0 + one line if installed, nonzero otherwise.
PLUGIN_DIR="$HOME/.config/omarchy/plugins/omx.apple-calendar"

[[ -f $PLUGIN_DIR/manifest.json && -f $PLUGIN_DIR/Panel.qml ]] || exit 1

bits=()
if systemctl --user is-enabled -q omx-apple-calendar-sync.timer 2>/dev/null; then
  bits+=("timer on")
else
  bits+=("timer off")
fi
if python3 -c "import caldav" 2>/dev/null; then
  bits+=("sync ready")
else
  bits+=("missing python deps")
fi
CACHE="${XDG_STATE_HOME:-$HOME/.local/state}/omx/apple-calendar/events.json"
if [[ -f $CACHE ]]; then
  bits+=("cache $(find "$CACHE" -printf '%TY-%Tm-%Td %TH:%TM' 2>/dev/null || echo present)")
else
  bits+=("no cache")
fi

echo "installed · $(IFS=,; echo "${bits[*]}")"
