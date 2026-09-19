#!/bin/bash
# Report install state. Exit 0 + one line if installed, nonzero otherwise.
BIN="$HOME/.local/bin/omarchy-agent-usage-opencode"
TIMER="$HOME/.config/systemd/user/omarchy-agent-usage-opencode.timer"

[[ -x $BIN && -f $TIMER ]] || exit 1

if systemctl --user is-enabled -q omarchy-agent-usage-opencode.timer 2>/dev/null; then
  echo "installed · timer enabled"
else
  echo "installed · timer disabled"
fi
