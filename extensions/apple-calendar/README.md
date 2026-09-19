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
| `sync/cal_sync.py` | `~/.local/bin/apple-cal-sync` |
| `omx-apple-calendar-sync.{service,timer}` | `~/.config/systemd/user/` (cache refresh, 15 min) |
| cache `events.json` | `~/.local/state/omx/apple-calendar/` |
| config (0600) | `~/.config/apple-calendar/config` |

## Install

```bash
./omx install apple-calendar            # widget + sync plumbing
apple-cal-sync login                    # Apple ID + app-specific password
apple-cal-sync sync                     # first fetch
./omx install apple-calendar --swap-clock   # replace bar clock (backs up shell.json)
```

The swap replaces the `omarchy.clock` bar entry with `omx.apple-calendar`
(keeping your label format) and the shell hot-reloads. Or swap manually:
point any `{"id": "omarchy.clock"}` entry at `omx.apple-calendar`
(`omarchy plugin enable omx.apple-calendar` also works once files are in place).

Python deps (`caldav`, `icalendar`, `recurring-ical-events`) are pip-installed
`--user` by the hook if missing.

## Uninstall

```bash
./omx uninstall apple-calendar            # code gone; credentials + cache kept
./extensions/apple-calendar/uninstall.sh --purge   # also delete credentials + cache
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
