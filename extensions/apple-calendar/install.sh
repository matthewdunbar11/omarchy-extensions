#!/bin/bash
# Install the apple-calendar bar widget + iCloud sync. Idempotent.
#   install.sh [--swap-clock]   also replace the bar's omarchy.clock entry
set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="omx.apple-calendar"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

# 1. Python deps for the sync script.
if ! python3 -c "import caldav, icalendar, recurring_ical_events" 2>/dev/null; then
  echo "Installing CalDAV deps (caldav, icalendar, recurring-ical-events)..."
  python3 -m pip install --user -q -r "$SRC/sync/requirements.txt"
fi

# 2. Shell plugin (hot-reloads on save).
mkdir -p "$PLUGIN_DIR"
cp "$SRC/plugin/manifest.json" "$SRC/plugin/BarWidget.qml" \
  "$SRC/plugin/Panel.qml" "$SRC/plugin/CalendarModel.js" "$PLUGIN_DIR/"

# 3. Sync script + systemd refresh timer.
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 0755 "$SRC/sync/cal_sync.py" "$HOME/.local/bin/apple-cal-sync"
install -m 0644 "$SRC/omx-apple-calendar-sync.service" "$SRC/omx-apple-calendar-sync.timer" \
  "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omx-apple-calendar-sync.timer

# 4. Optional: swap the bar's stock clock for this widget (backup first).
if [[ ${1:-} == "--swap-clock" ]]; then
  SHELL_JSON="$HOME/.config/omarchy/shell.json"
  BACKUP="$SHELL_JSON.bak.$(date +%s)"
  cp "$SHELL_JSON" "$BACKUP"
  python3 - "$SHELL_JSON" <<'EOF'
import json, sys
path = sys.argv[1]
d = json.load(open(path))
def swap(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "layout" and isinstance(v, dict):
                for section, items in v.items():
                    if isinstance(items, list):
                        for i, it in enumerate(items):
                            if isinstance(it, dict) and it.get("id") == "omarchy.clock":
                                entry = {"id": "omx.apple-calendar"}
                                for keep in ("format", "formatAlt"):
                                    if keep in it:
                                        entry[keep] = it[keep]
                                items[i] = entry
            else:
                swap(v)
    elif isinstance(node, list):
        for it in node:
            swap(it)
swap(d)
json.dump(d, open(path, "w"), indent=2)
print("bar entry swapped (backup kept)")
EOF
  echo "Backup: $BACKUP (shell hot-reloads the layout)"
fi

echo "apple-calendar installed. Next: apple-cal-sync login"
echo "(needs an APP-SPECIFIC password from appleid.apple.com)"
