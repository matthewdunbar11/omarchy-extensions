#!/bin/bash
# Install the apple-calendar bar widget + iCloud sync. Idempotent.
# Asks about swapping the bar clock and signing in on a TTY
# (--swap-clock/--no-swap-clock and --login/--no-login override;
# non-interactive defaults to no swap, no login).
set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="omx.apple-calendar"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

SWAP=""
LOGIN=""
for a in "$@"; do
  case $a in
    --swap-clock) SWAP=yes ;;
    --no-swap-clock) SWAP=no ;;
    --login) LOGIN=yes ;;
    --no-login) LOGIN=no ;;
  esac
done

ask() { # prompt -> yes/no; non-interactive always no
  local prompt=$1 ans
  if [[ -t 0 ]]; then
    read -rp "$prompt [y/N] " ans
    [[ $ans == [yY]* ]] && echo yes || echo no
  else
    echo no
  fi
}

[[ -n $SWAP ]] || SWAP=$(ask "Replace the bar's stock clock with Apple Calendar?")
if [[ -f $HOME/.config/apple-calendar/config ]]; then
  echo "(already signed in — skipping sign-in question)"
  LOGIN=no
elif [[ -z $LOGIN ]]; then
  LOGIN=$(ask "Sign in to iCloud Calendar now (Apple ID + app-specific password)?")
fi

APPDIR="${XDG_DATA_HOME:-$HOME/.local/share}/omx/apple-calendar"
VENV="$APPDIR/.venv"

# 1. Self-contained venv for the sync script: system python has no pip and no
#    CalDAV libs, and we install nothing system-wide and need no sudo.
#    Non-fatal throughout: status.sh reports the gap; sync waits for deps.
mkdir -p "$APPDIR"
if [[ ! -x $VENV/bin/python ]]; then
  echo "Creating private venv (this takes ~30s once)..."
  python3 -m venv "$VENV" || echo "WARNING: venv creation failed" >&2
fi
if [[ -x $VENV/bin/python ]]; then
  if ! "$VENV/bin/python" -c "import caldav, icalendar, recurring_ical_events" 2>/dev/null; then
    echo "Installing CalDAV deps into the private venv..."
    "$VENV/bin/pip" install -q -r "$SRC/sync/requirements.txt" || {
      echo "WARNING: pip install failed — sync will fail until fixed:" >&2
      echo "  $VENV/bin/pip install -r $SRC/sync/requirements.txt" >&2
    }
  fi
else
  echo "WARNING: no venv python — sync cannot run on this machine yet." >&2
fi
cp "$SRC/sync/cal_sync.py" "$APPDIR/cal_sync.py"

# 2. Shell plugin (hot-reloads on save).
mkdir -p "$PLUGIN_DIR"
cp "$SRC/plugin/manifest.json" "$SRC/plugin/BarWidget.qml" \
  "$SRC/plugin/Panel.qml" "$SRC/plugin/CalendarModel.js" "$PLUGIN_DIR/"

# 3. Sync entrypoint (shim: prefers the private venv, falls back to system
#    python3) + systemd refresh timer.
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 0755 "$SRC/apple-cal-sync" "$HOME/.local/bin/apple-cal-sync"
install -m 0644 "$SRC/omx-apple-calendar-sync.service" "$SRC/omx-apple-calendar-sync.timer" \
  "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omx-apple-calendar-sync.timer

# 4. Optional: swap the bar's stock clock for this widget (backup first).
if [[ $SWAP == yes ]]; then
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

# 5. Optional: sign in + first sync right away (read-only CalDAV fetch).
if [[ $LOGIN == yes ]]; then
  if "$HOME/.local/bin/apple-cal-sync" login; then
    "$HOME/.local/bin/apple-cal-sync" sync || true
  fi
else
  echo "When ready: apple-cal-sync login   (APP-SPECIFIC password from appleid.apple.com)"
  echo "            apple-cal-sync sync"
fi

echo "apple-calendar installed."
