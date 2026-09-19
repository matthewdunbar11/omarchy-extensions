# omarchy-extensions

Community extensions for [Omarchy](https://omarchy.org/) that aren't (only)
shell plugins: collectors, background programs, browser integrations,
customizations — anything that improves the Omarchy desktop.

Each extension lives in its own directory under `extensions/` with everything
needed to install it. A top-level TUI manager (install/uninstall per
extension) is on the roadmap; until then, each extension's README documents
manual install steps.

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
