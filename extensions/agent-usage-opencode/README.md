# agent-usage-opencode

Kind: **agents-panel collector** (program + systemd timer, not a shell plugin).

Feeds an "Opencode Go" usage record to Omarchy's stock `agents` bar widget:
API limits from `https://opencode.ai/zen/go/v1/usage` plus local stats from
opencode session data. The panel picks the record up with zero plugin changes
(it renders any record that lands in the usage dir).

No secrets embedded — the API key is read from env (`OPENCODE_GO_API_KEY`,
`OPENCODE_API_KEY`, or `ZEN_API_KEY`) at runtime.

## Files

| File | Installed to |
|------|--------------|
| `omarchy-agent-usage-opencode` | `~/.local/bin/` (executable) |
| `omarchy-agent-usage-opencode.service` | `~/.config/systemd/user/` |
| `omarchy-agent-usage-opencode.timer` | `~/.config/systemd/user/` |

## Install

```bash
cd extensions/agent-usage-opencode
install -m 0755 omarchy-agent-usage-opencode ~/.local/bin/
install -m 0644 omarchy-agent-usage-opencode.{service,timer} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now omarchy-agent-usage-opencode.timer
```

Needs: opencode with an OpenCode Go subscription (`/connect` in opencode,
or export one of the `*_API_KEY` vars above).

## Uninstall

```bash
systemctl --user disable --now omarchy-agent-usage-opencode.timer
rm ~/.config/systemd/user/omarchy-agent-usage-opencode.{service,timer}
rm ~/.local/bin/omarchy-agent-usage-opencode
rm -f ~/.local/state/omarchy/agents/usage/opencode.json
systemctl --user daemon-reload
```

## Check

```bash
omarchy-agent-usage-opencode --limits-only | head -c 300
systemctl --user list-timers | grep opencode
cat ~/.local/state/omarchy/agents/usage/opencode.json | head -c 300
```
