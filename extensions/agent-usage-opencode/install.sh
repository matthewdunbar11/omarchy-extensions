#!/bin/bash
# Install the agent-usage-opencode collector. Idempotent: safe to re-run.
set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 0755 "$SRC/omarchy-agent-usage-opencode" "$HOME/.local/bin/"
install -m 0644 "$SRC/omarchy-agent-usage-opencode.service" "$SRC/omarchy-agent-usage-opencode.timer" \
  "$HOME/.config/systemd/user/"

systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-opencode.timer

echo "agent-usage-opencode installed (timer enabled, 15min refresh)."
