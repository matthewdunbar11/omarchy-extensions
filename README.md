# omarchy-extensions

Community extensions for [Omarchy](https://omarchy.org/) that aren't (only)
shell plugins: collectors, background programs, browser integrations,
customizations — anything that improves the Omarchy desktop.

Each extension lives in its own directory under `extensions/` with everything
needed to install it. The [`omx`](omx) manager provides a TUI + CLI over them:

```bash
./omx              # interactive picker (extension -> install/uninstall/status)
./omx list
./omx install agent-usage-opencode
./omx uninstall agent-usage-opencode --yes
```

## Extension contract

An extension is a directory `extensions/<name>/` containing:

| File | Required | Purpose |
|------|----------|---------|
| `meta.sh` | yes | `NAME=`, `KIND=`, `DESC=`, `VERSION=` (sourced, keep it assignments-only) |
| `install.sh` | yes | idempotent install into user space (`$HOME`-relative, no sudo) |
| `uninstall.sh` | yes | complete removal incl. state; tolerate missing pieces (`\|\| true`) |
| `status.sh` | yes | exit 0 + one-line state if installed, nonzero otherwise |
| `README.md` | yes | what/why + manager and manual install/uninstall steps |

Rules: user-space only (`~/.local/bin`, `~/.config/systemd/user`,
`~/.config/omarchy`) — never `/usr/share/omarchy/`, never sudo.

## Layout

```
extensions/
  <name>/
    README.md          # what it is + how to install/uninstall
    ...files...        # scripts, systemd units, configs, themes
```

## Extensions

| Name | Kind | Description |
|------|------|-------------|
| [agent-usage-opencode](extensions/agent-usage-opencode/) | agents-panel collector | "Opencode Go" usage record (API limits + local stats) for the stock agents widget |

## Adding an extension

1. Create `extensions/<name>/` with the files and a README (what/why/how to install/how to uninstall).
2. Keep secrets out — collectors must read API keys from env/keyring at runtime, never embed them.
3. Never touch `/usr/share/omarchy/` — user-space only (`~/.local/bin`, `~/.config/systemd/user`, `~/.config/omarchy`).

## License

MIT — see [LICENSE](LICENSE).
