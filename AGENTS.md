# AGENTS.md - omarchy-extensions

<instructions>
Community extensions for Omarchy (collectors, programs, customizations —
not only shell plugins), managed by the `omx` TUI. Extensions own the how
(install/uninstall/status hooks); `omx` fans out.
</instructions>

## Dev Flow
- `./omx list` - MUST run to see extensions + live state before changing anything.
- `bash -n <script>` - MUST pass on every shell file before commit.
- Sandbox test for install/uninstall changes - MUST use fake HOME + stub
  `systemctl` (see "Verification"), NEVER against the live system.
- `./omx status <name>` - MUST report installed state after hook changes.

<rules>
## Extension Contract (`extensions/<name>/`)
- MUST ship `meta.sh` (assignments only: `NAME=`, `KIND=`, `DESC=`,
  `VERSION=`), `install.sh`, `uninstall.sh`, `status.sh`, `README.md`.
- `install.sh` MUST be idempotent (safe re-run) and `$HOME`-relative.
- `uninstall.sh` MUST remove binary, units, and state; MUST tolerate missing
  pieces (`|| true` on systemctl/rm paths that may not exist).
- `status.sh` MUST exit 0 + one line if installed, nonzero otherwise, and
  MUST NOT have side effects.
- Install-complete rule: answering an extension's install questions (via the
  omx TUI or hooks) MUST leave it working with ZERO manual follow-up
  commands. Hooks perform first-sync/first-fetch themselves, schedule
  background refresh, and degrade to a pending state — the UI must never send
  the user to a terminal for setup the installer could have done.
- Hooks own their questions: ask on a TTY (`[[ -t 0 ]]`), honor explicit
  flags (`--swap-clock/--no-swap-clock`, `--purge/--keep-data` style), and
  take safe defaults when non-interactive (no swap, keep data). `omx` never
  forwards flags — it only fans out.
- `omx` sources `meta.sh` in a subshell and must work with or without gum
  (select fallback); keep that fallback working.

## Safety & Constraints
- MUST NOT touch `/usr/share/omarchy/` (read-only, package-owned).
- MUST NOT use sudo; everything is user-space (`~/.local/bin`,
  `~/.config/systemd/user`, `~/.config/omarchy`).
- MUST NOT embed secrets — collectors read API keys from env/keyring at
  runtime. Grep for embedded tokens before every commit touching collectors.
- MUST NOT run an extension's `install.sh`/`uninstall.sh` against the real
  `$HOME` for testing — sandbox only. Live state (e.g. a running collector
  + timer) MUST keep running untouched.
- MUST NOT commit without `bash -n` passing on all touched shell files.

## Verification (sandbox)
```bash
rm -rf /tmp/omxtest && mkdir -p /tmp/omxtest/home /tmp/omxtest/fakebin
cp -r . /tmp/omxtest/repo
printf '#!/bin/bash\necho "stub $@" >> /tmp/omxtest/calls.log\nexit 0\n' \
  > /tmp/omxtest/fakebin/systemctl && chmod +x /tmp/omxtest/fakebin/systemctl
export HOME=/tmp/omxtest/home PATH=/tmp/omxtest/fakebin:$PATH
/tmp/omxtest/repo/omx list                       # expect: not installed
/tmp/omxtest/repo/omx install <name> --yes
/tmp/omxtest/repo/omx status <name>              # expect: installed
/tmp/omxtest/repo/omx uninstall <name> --yes
find /tmp/omxtest/home -type f                   # expect: empty
```

## Routing
- Manager: `omx` (root). Extension lookup: `extensions/`.
- New extension? Copy the layout of `extensions/agent-usage-opencode/`.
- Agent-facing docs: `skills/omarchy-extensions/SKILL.md`.
</rules>

<context_hints>
- `omx` - Manager (fan-out, gum TUI + CLI, symlink-safe root detection).
- `extensions/agent-usage-opencode/` - Reference extension (collector +
  systemd timer for the stock agents widget).
- `skills/omarchy-extensions/SKILL.md` - Skill for agents managing extensions.
- **Ignore**: `.git/`.
</context_hints>
