#!/usr/bin/env python3
"""cal_sync — iCloud Calendar (CalDAV) -> JSON cache for the apple-calendar panel.

Auth uses an APP-SPECIFIC password (create at appleid.apple.com -> Sign-In &
Security -> App-Specific Passwords), NOT your Apple ID password. No escrow,
no HSM, no device passcode anywhere in this flow — CalDAV basic-auth only.

Usage:
  cal_sync.py login                 # prompt Apple ID + app-specific password, save 0600 config
  cal_sync.py logout                # delete config
  cal_sync.py sync [--quiet]        # fetch +/-120d, expand recurring, atomic cache write
  cal_sync.py sync --from-ics f.ics # offline path (tests): parse file, same pipeline

Cache:  ~/.local/state/omx/apple-calendar/events.json
Config: ~/.config/apple-calendar/config (0600 JSON)
"""
from __future__ import annotations

import getpass
import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

CALDAV_URL = "https://caldav.icloud.com"
WINDOW_DAYS = 120


def config_path() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "apple-calendar" / "config"


def cache_path() -> Path:
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
    return state / "omx" / "apple-calendar" / "events.json"


def load_config() -> dict:
    p = config_path()
    if not p.exists():
        raise SystemExit("Not logged in. Run: cal_sync.py login  (needs an APP-SPECIFIC password)")
    return json.loads(p.read_text())


def cmd_login() -> None:
    apple_id = input("Apple ID (you@icloud.com): ").strip()
    app_pw = getpass.getpass("App-specific password (appleid.apple.com -> App-Specific Passwords): ").strip()
    if not apple_id or not app_pw:
        raise SystemExit("Both are required.")
    p = config_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps({"apple_id": apple_id, "app_password": app_pw}))
    os.chmod(p, 0o600)
    print(f"Saved to {p} (mode 0600). Now run: cal_sync.py sync")


def cmd_logout() -> None:
    p = config_path()
    if p.exists():
        p.unlink()
        print("Logged out (config deleted).")
    else:
        print("Not logged in.")


def _local_tz():
    return datetime.now().astimezone().tzinfo


def _as_local(value, tz):
    """icalendar DATE/DATETIME -> local datetime or date."""
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=tz)
        return value.astimezone(tz)
    return value  # date


def expand_components(components, tz) -> dict:
    """VEVENT occurrences -> {dateKey: [event]}. Skips cancelled + dupes
    (direct walk and recurrence expansion can yield the same occurrence)."""
    days: dict[str, list[dict]] = {}
    seen: set[tuple] = set()
    for comp in components:
        if comp.get("status", "").upper() == "CANCELLED":
            continue
        title = str(comp.get("summary", "(No title)")).strip() or "(No title)"
        cal_name = str(comp.get("_cal_name", ""))
        raw_start = comp.get("dtstart").dt if comp.get("dtstart") else None
        raw_end = comp.get("dtend").dt if comp.get("dtend") else None
        if raw_start is None:
            continue
        start = _as_local(raw_start, tz)
        end = _as_local(raw_end, tz) if raw_end is not None else None
        all_day = isinstance(start, date) and not isinstance(start, datetime)
        ident = (str(comp.get("uid", "")), str(start), str(end))
        if ident in seen:
            continue
        seen.add(ident)
        if all_day:
            end_date = end if isinstance(end, date) and not isinstance(end, datetime) else start
            # DTEND on all-day is exclusive; guard empty/negative spans.
            span = max(1, (end_date - start).days)
            span = min(span, 62)
            for i in range(span):
                d = start + timedelta(days=i)
                days.setdefault(d.isoformat(), []).append({
                    "title": title, "start": "", "end": "",
                    "allDay": True, "calendar": cal_name,
                })
        else:
            end = end if isinstance(end, datetime) else start
            if end < start:
                end = start
            # Split multi-day occurrences across each local day.
            day = start.date()
            last = end.date()
            guard = 0
            while day <= last and guard < 62:
                days.setdefault(day.isoformat(), []).append({
                    "title": title,
                    "start": start.strftime("%H:%M") if day == start.date() else "",
                    "end": end.strftime("%H:%M") if day == end.date() else "",
                    "allDay": False, "calendar": cal_name,
                })
                day += timedelta(days=1)
                guard += 1
    for evs in days.values():
        evs.sort(key=lambda e: (0 if e["allDay"] else 1, e["start"], e["title"]))
    return days


def calendars_from_caldav(client) -> list[tuple[str, object]]:
    try:
        principal = client.principal()
    except Exception as e:
        print(f"warning: principal lookup failed: {e}", file=sys.stderr)
        return []
    try:
        cals = principal.calendars()
    except Exception as e:
        print(f"warning: calendar listing failed: {e}", file=sys.stderr)
        return []
    out = []
    for cal in cals:
        try:
            name = cal.name or str(cal.url)
        except Exception:
            name = "Calendar"
        out.append((name, cal))
    return out


def fetch_live(cfg: dict, start: datetime, end: datetime):
    import caldav
    import recurring_ical_events
    from icalendar import Calendar

    client = caldav.DAVClient(url=CALDAV_URL, username=cfg["apple_id"], password=cfg["app_password"])
    components = []
    n_cals = 0
    for name, cal in calendars_from_caldav(client):
        n_cals += 1
        try:
            results = cal.date_search(start=start, end=end, expand=True)
        except Exception as e:
            print(f"warning: {name}: date_search failed ({e}), trying raw fetch", file=sys.stderr)
            try:
                results = cal.events()
            except Exception as e2:
                print(f"warning: {name}: skipped ({e2})", file=sys.stderr)
                continue
        for ev in results:
            try:
                ical = Calendar.from_ical(ev.data)
            except Exception:
                continue
            for comp in ical.walk("VEVENT"):
                comp["_cal_name"] = name
                components.append(comp)
        # Expand recurring client-side too (server expand varies).
        try:
            for ev in results:
                try:
                    calobj = Calendar.from_ical(ev.data)
                    for occ in recurring_ical_events.of(calobj).between(start, end):
                        if occ.name == "VEVENT":
                            occ["_cal_name"] = name
                            # avoid double-counting non-recurring already added
                            if occ.get("rrule") or occ.get("recurrence-id"):
                                components.append(occ)
                except Exception:
                    continue
        except Exception:
            pass
    if n_cals == 0:
        # Every iCloud account has at least one calendar: zero listed means
        # auth/network failure, never "no data". Fail loudly so callers
        # (install.sh, timers) don't mistake it for an empty-but-good sync.
        raise SystemExit("could not list any iCloud calendars — "
                         "check the Apple ID / app-specific password and network")
    return components, n_cals


def fetch_from_ics(path: str):
    from icalendar import Calendar
    data = Path(path).read_bytes()
    calobj = Calendar.from_ical(data)
    out = []
    for comp in calobj.walk("VEVENT"):
        comp["_cal_name"] = "Test"
        out.append(comp)
    # Expand recurring for the fixture the same way.
    try:
        import recurring_ical_events
        now = datetime.now().astimezone()
        start = now - timedelta(days=WINDOW_DAYS)
        end = now + timedelta(days=WINDOW_DAYS)
        for occ in recurring_ical_events.of(calobj).between(start, end):
            if occ.name == "VEVENT" and (occ.get("rrule") or occ.get("recurrence-id")):
                occ["_cal_name"] = "Test"
                out.append(occ)
    except Exception:
        pass
    return out


def cmd_sync(args: list[str]) -> None:
    quiet = "--quiet" in args
    from_ics = args[args.index("--from-ics") + 1] if "--from-ics" in args else None
    tz = _local_tz()
    now = datetime.now(tz)
    if from_ics:
        components = fetch_from_ics(from_ics)
        n_cals = 1
    else:
        cfg = load_config()
        start = now - timedelta(days=WINDOW_DAYS)
        end = now + timedelta(days=WINDOW_DAYS)
        components, n_cals = fetch_live(cfg, start, end)
    days = expand_components(components, tz)
    payload = {
        "days": days,
        "synced_at": now.isoformat(),
        "calendars": n_cals,
        "total_events": sum(len(v) for v in days.values()),
    }
    out = cache_path()
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload))
    os.replace(tmp, out)
    if not quiet:
        print(f"synced {payload['total_events']} events across {len(days)} days "
              f"from {n_cals} calendar(s) -> {out}")


def main(argv: list[str]) -> None:
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print(__doc__)
        return
    if argv[1] == "login":
        cmd_login()
    elif argv[1] == "logout":
        cmd_logout()
    elif argv[1] == "sync":
        cmd_sync(argv[2:])
    else:
        raise SystemExit(f"Unknown command: {argv[1]}")


if __name__ == "__main__":
    main(sys.argv)
