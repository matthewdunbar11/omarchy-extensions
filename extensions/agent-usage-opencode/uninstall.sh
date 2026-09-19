#!/bin/bash
# Uninstall the agent-usage-opencode collector. Removes binary, units, and state.
set -euo pipefail

systemctl --user disable --now omarchy-agent-usage-opencode.timer 2>/dev/null || true

rm -f "$HOME/.config/systemd/user/omarchy-agent-usage-opencode.service" \
  "$HOME/.config/systemd/user/omarchy-agent-usage-opencode.timer" \
  "$HOME/.local/bin/omarchy-agent-usage-opencode" \
  "$HOME/.local/state/omarchy/agents/usage/opencode.json"

systemctl --user daemon-reload 2>/dev/null || true

echo "agent-usage-opencode uninstalled."
