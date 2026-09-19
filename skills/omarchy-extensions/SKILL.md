---
name: omarchy-extensions
description: >
  Manage the omarchy-extensions repo (~/Projects/omarchy-extensions):
  community Omarchy customizations beyond shell plugins (collectors,
  programs, hooks) installed via the omx TUI manager. Use when adding a new
  extension, editing install/uninstall/status hooks, or installing,
  uninstalling, or checking state of an omarchy-extension. Triggers: omx,
  omarchy-extensions, omarchy extension install/uninstall, agents-panel
  collector. Never touches /usr/share/omarchy/; user-space only, no sudo.
---

# Omarchy Extensions Skill

The `omarchy-extensions` repo (`~/Projects/omarchy-extensions`, GitHub:
`matthewdunbar11/omarchy-extensions`) hosts community Omarchy customizations
that aren't shell plugins — collectors, background programs, browser
integrations — plus the `omx` manager (TUI + CLI) that installs/uninstalls
each one. Extensions own the how; `omx` fans out.

## The Contract

Every extension is `extensions/<name>/` with:

| File | Purpose |
|------|---------|
| `meta.sh` | Assignments only: `NAME=`, `KIND=`, `DESC=`, `VERSION=` |
| `install.sh` | Idempotent install, `$HOME`-relative paths |
| `uninstall.sh` | Full removal incl. state; tolerate missing pieces |
| `status.sh` | Exit 0 + one-line state if installed, nonzero otherwise |
| `README.md` | What/why + manager and manual steps |

Reference implementation: `extensions/agent-usage-opencode/` (collector +
systemd timer feeding the stock agents widget).

## Manager Usage

```bash
omx                          # TUI picker (needs repo on PATH via ~/.local/bin/omx)
omx list                     # extensions + live state (run this FIRST)
omx install <name> [--yes]
omx uninstall <name> [--yes]
omx status <name>
./omx <cmd>                  # from repo root if not on PATH
```

## Safety Rules

- **User-space only.** `~/.local/bin`, `~/.config/systemd/user`,
  `~/.config/omarchy`. NEVER `/usr/share/omarchy/`, NEVER sudo.
- **Sandbox destructive tests.** Never run `install.sh`/`uninstall.sh`
  against the real `$HOME` to test — use fake `HOME` + stub `systemctl`
  (exact recipe in `AGENTS.md` under "Verification").
- **No embedded secrets.** Collectors read API keys from env/keyring at
  runtime. Grep before committing collector changes.
- **`bash -n` every touched shell file** before commit.
- Live state (running collectors/timers) stays untouched by testing.

## Adding an Extension

1. Create `extensions/<name>/` with the five contract files
   (copy `agent-usage-opencode/` as the template).
2. Verify: `bash -n` on all scripts, sandbox install/status/uninstall
   round-trip per `AGENTS.md`, plus live `./omx list` showing correct state.
3. Commit (repo convention: short imperative subjects) and push to `main`.
