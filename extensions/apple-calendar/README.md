# apple-calendar

Kind: **bar-widget** — a replacement date/time label + calendar popup wired to
**iCloud Calendar**. Month grid dots the days that have events; clicking a day
lists its events along the bottom of the panel.

Auth is CalDAV with an **app-specific password** (appleid.apple.com → Sign-In
& Security → App-Specific Passwords) — not your Apple ID password, no 2FA
dance, no escrow, no HSM. Nothing is ever written to iCloud (read-only sync).

## Files

| Path | Installed to |
|------|--------------|
| `plugin/` (manifest, BarWidget, Panel, CalendarModel.js) | `~/.config/omarchy/plugins/omx.apple-calendar/` |
| `sync/cal_sync.py` | `~/.local/share/omx/apple-calendar/` + private `.venv` there |
| `apple-cal-sync` (shim) | `~/.local/bin/` (prefers the venv, falls back to system python3) |
| `omx-apple-calendar-sync.{service,timer}` | `~/.config/systemd/user/` (cache refresh, 15 min) |
| cache `events.json` | `~/.local/state/omx/apple-calendar/` |
| config (0600) | `~/.config/apple-calendar/config` |

## Install

```bash
./omx install apple-calendar
```

On install the hook asks two questions (TTY only; scripted runs say no):
1. Replace the bar's `omarchy.clock` entry? (backup kept next to
   `shell.json`, shell hot-reloads; your label format is preserved.
   `--swap-clock` / `--no-swap-clock` force it.)
2. Sign in now? Runs `apple-cal-sync login` (Apple ID + app-specific
   password from appleid.apple.com) followed by a first `sync`.
   (`--login` / `--no-login` force it.)

Python deps (`caldav`, `icalendar`, `recurring-ical-events`) live in a private
venv under `~/.local/share/omx/apple-calendar/` — created by the hook, no
sudo, nothing system-wide. System python needs nothing (not even pip).

## Uninstall

```bash
./omx uninstall apple-calendar            # asks about purging credentials + cache
```

Point the bar back at `omarchy.clock` if you swapped (a `shell.json.bak.*`
sits next to `shell.json`).

## Check

```bash
./omx status apple-calendar
omarchy plugin validate extensions/apple-calendar/plugin
cat ~/.local/state/omx/apple-calendar/events.json | head -c 300
```

## Troubleshooting

- Panel says "No iCloud events yet": `apple-cal-sync login`, then `sync`.
  Main Apple ID password will NOT work — it must be an app-specific password.
- Dots missing after adding events on iPhone: refresh button (↻) in the panel,
  or `systemctl --user start omx-apple-calendar-sync.service`.
- Times look off: events render in your local timezone; all-day events show
  "All day".
