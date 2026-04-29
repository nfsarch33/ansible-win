# Windows-MCP runbook — devops-sysadmin skill

Canonical reference for operating `uvx windows-mcp` under the
`devops-sysadmin` IronClaw skill on every Windows 11 fleet node. Complements
`win1-rollout.md` (rollout steps) and ADR-015 (policy). Upstream project:
`~/Windows-MCP/` (git mirror of
[CursorTouch/Windows-MCP](https://github.com/CursorTouch/Windows-MCP)).

## Scope

Windows-MCP is the stdio MCP server that gives IronClaw (running on WSL1 or
on the Windows host) structured control of the Windows OS — UI automation,
PowerShell shell, screenshots, clipboard, filesystem, registry, processes.
It is the **primary** Windows control plane for `devops-sysadmin`.

> Security note. Windows-MCP ships tools that can cause irreversible damage
> (`PowerShell`, `FileSystem` write/delete modes, `Registry`, `Process`
> `kill`). See `~/Windows-MCP/SECURITY.md` for the upstream warning. Deploy
> only on dedicated fleet nodes and honour the gated-tool list below.

## Upstream mirror is reference-only

`~/Windows-MCP/` is a **read-only git mirror**. Do not edit files there; do
not deploy it as the production path. The production path is always
`uvx windows-mcp@<pinned-version>` from PyPI via the `devops-sysadmin`
installer. The mirror exists to:

1. Let operators read upstream source during incident response
   (`~/Windows-MCP/src/windows_mcp/tools/*.py`).
2. Diff new upstream versions against the pinned version before bumping.
3. Anchor documentation (`CLAUDE.md`, `SECURITY.md`, `manifest.json`) to a
   known commit.

To update the mirror:

```bash
cd ~/Windows-MCP && git pull --ff-only origin main
```

If upstream moved ahead of the pinned version, plan a bump (see
`Upgrade flow` below). Never hand-edit files inside the mirror.

## Pinned version

Single source of truth: `skills/devops-sysadmin/telemetry/windows-mcp.version`
on each node. The installer writes this file after probing the pinned spec.

| Channel | Pin         | Driver                                                   |
| ------- | ----------- | -------------------------------------------------------- |
| Windows | `0.7.1`     | `install.ps1 -WindowsMcpVersion 0.7.1` (default)         |
| WSL     | `0.7.1`     | `WINDOWS_MCP_VERSION=0.7.1 install.sh` (default)         |
| Config  | `0.7.1`     | `windows-mcp-config.json._windowsMcpVersion` (JSON meta) |
| Config  | `0.7.1`     | `windows-mcp-config.wsl.toml` (`version = "0.7.1"`)      |

Bump flow is described in `Upgrade flow` at the end of this runbook.

## Tool surface (v0.7.1, 18 tools)

Windows-MCP exposes 18 tools. IronClaw's MCP client enforces a three-tier
policy: `read` (read-only observation), `control` (active host changes),
`gated` (extra approval needed because the blast radius is large or
irreversible). The Windows-side JSON config uses the simpler
`allowedTools` + `gatedTools` split.

| Tool          | Tier    | JSON `allowed` | JSON `gated` | WSL `read`/`control` | WSL `gated` | Notes                                                 |
| ------------- | ------- | -------------- | ------------ | -------------------- | ----------- | ----------------------------------------------------- |
| App           | read    | yes            | no           | read                 | no          | launch/resize/switch windows                          |
| Process       | read    | yes            | yes          | read                 | yes         | `list` safe, `kill` requires approval on both sides   |
| Screenshot    | read    | yes            | no           | read                 | no          | fast desktop capture                                  |
| Snapshot      | read    | yes            | no           | read                 | no          | UI tree + optional DOM                                |
| Clipboard     | read    | yes            | no           | read                 | no          | `get`/`set` text                                      |
| FileSystem    | mixed   | yes            | yes          | read + control       | yes         | **NEW in 0.7.1**; `write`/`delete` need approval      |
| PowerShell    | control | yes            | no           | control              | no          | full shell — treat every call as privileged           |
| Click         | control | yes            | no           | control              | no          | synthetic mouse click                                 |
| Type          | control | yes            | no           | control              | no          | synthetic keyboard typing                             |
| Scroll        | control | yes            | no           | control              | no          | wheel scroll                                          |
| Move          | control | yes            | no           | control              | no          | cursor move / drag                                    |
| Shortcut      | control | yes            | no           | control              | no          | keyboard shortcut chords                              |
| Wait          | control | yes            | no           | control              | no          | sleep; no state change                                |
| MultiSelect   | control | yes            | no           | control              | no          | ctrl-click for selections                             |
| MultiEdit     | control | yes            | no           | control              | no          | type into multiple inputs                             |
| Notification  | control | yes            | no           | control              | no          | toast notifications                                   |
| Scrape        | control | yes            | no           | control              | no          | URL fetch                                             |
| Registry      | gated   | no (gated)     | yes          | read                 | yes         | `Registry get/set/delete`; ADR-015 §9 requires ticket |

Rules:

- **Do not promote `Registry` out of `gatedTools`.** Registry writes brick
  hosts in subtle ways and there is no generic rollback. Registry reads
  (`mode=list`, `mode=get`) are permitted via the `read` tier on the WSL
  bridge but must still be justified in the session log.
- **`FileSystem` is elevated-risk even though PowerShell is allowed.** Keep
  it in `gatedTools` on **both** config surfaces for routine ops;
  `PowerShell` already covers ad-hoc one-offs, and the structured FileSystem
  tool is the vector most likely to be called implicitly by agent
  chain-of-thought. Production use requires a logged ticket or an explicit
  `/approve fs:<op>` token.
- **`Process` is gated wholesale on both surfaces.** The TOML and JSON both
  list `Process` under `gated`/`gatedTools`. `Process list` is safe in
  principle but we prefer a coarse approval gate over per-argument policy
  engine checks; if this proves noisy, graduate `Process list` to `allowed`
  only after adding an explicit mode-sniffer to the dispatcher.
- **Never ship Windows-MCP with `ANONYMIZED_TELEMETRY=true`.** The skill
  config pins it to `false` for all three config surfaces (install.ps1,
  windows-mcp-config.json, windows-mcp-config.wsl.toml).

## Bringing a node online

Follow `win1-rollout.md` (Phases 1–3). The Windows-MCP-specific acceptance
tests are:

```powershell
# Windows host (run after install.ps1):
uvx windows-mcp@0.7.1 --help | Select-Object -First 1      # pinned entry
Get-Content "$env:USERPROFILE\.ironclaw\skills\devops-sysadmin\telemetry\windows-mcp.version"
Get-Content "$env:USERPROFILE\.ironclaw\skills\devops-sysadmin\telemetry\windows-mcp.sha"
```

```bash
# WSL1 (run after install.sh):
cat ~/.cursor/skills/ironclaw-win-sysadmin/telemetry/windows-mcp.version
cat ~/.cursor/skills/ironclaw-win-sysadmin/telemetry/wslbridge.txt | head -1
powershell.exe -NoLogo -NonInteractive -Command 'uvx windows-mcp@0.7.1 --help' | head -1
```

All three `.version` / `.sha` / bridge probes must agree on `0.7.1`.

## Drift detection (live)

`scripts/preflight.ps1` and `scripts/preflight.sh` (in this skill) run every
3 minutes via scheduled task / systemd timer. They call
`scripts/check-windows-mcp-version.(ps1|sh)` which:

1. Reads `telemetry/windows-mcp.version`.
2. Runs `uvx windows-mcp@<pinned> --help` and fails if uvx resolves a
   different version (confirming that uvx's cached resolution is still
   deterministic).
3. Re-computes the sha256 prefix of `--help` stdout and compares it to
   `telemetry/windows-mcp.sha`.
4. Writes a Prometheus text-format metric to
   `telemetry/windows-mcp-drift.prom`:

   ```prometheus
   windows_mcp_version_pin{node="win1",pin="0.7.1"} 1
   windows_mcp_drift{node="win1",pin="0.7.1"} 0
   ```

   `drift=1` is a pagerable event.

See `Add version-drift check script` section below for the scripts.

## Upgrade flow

Only bump the pin when (a) upstream fixes a security or correctness bug
that affects fleet agents, (b) a new tool is needed by an approved skill,
or (c) we are chasing a matching Python 3.13 dependency.

Sequence:

1. **Diff upstream.** `cd ~/Windows-MCP && git pull --ff-only origin main`
   then `git log --oneline v0.7.1..HEAD -- src/windows_mcp/tools` and
   `git diff v0.7.1..HEAD -- manifest.json`. Attach the diff to the bump
   ticket.
2. **Read upstream SECURITY.md diff.** Block if new risks emerged without a
   mitigation plan.
3. **Stage pin change on a feature branch** in `ai-agent-business-stack`:

   ```bash
   cd ~/ai-agent-business-stack
   git checkout -b chore/windows-mcp-0.8.0
   # Bump:
   # - install.ps1 param default
   # - install.sh WINDOWS_MCP_VERSION
   # - windows-mcp-config.json "_windowsMcpVersion" + args
   # - windows-mcp-config.wsl.toml version + args
   # - runbooks/windows-mcp.md (this file, pin table + heading)
   ```

4. **Dry-run on one node first.** Prefer `win1`. Run `install.ps1 -NoOp`
   and `install.sh` to confirm probes pass; then run for real. Keep
   `win2`/`win3` on the previous pin until `win1` is green for 24h.
5. **Roll forward.** `./scripts/fleet/fleet-onboard-node.sh --with-devops-skill win2`
   per node. Each run refreshes the canonical path and the telemetry
   files.
6. **Verify drift metric.** `windows_mcp_drift` must stay `0` on all three
   nodes for the next preflight cycle.
7. **Commit + tag.** `feat(devops-sysadmin): bump windows-mcp pin to 0.8.0`.
8. **Close the upstream-mirror delta.** Re-run `git log` after the bump to
   ensure the mirror HEAD matches the new pin; tag the mirror locally with
   `git tag local-pin-0.8.0` so future diffs start from a clean point.

## Incident playbooks

### `wslbridge.txt` probe shows `access denied`

- Cause: UAC elevation step during `install.ps1` did not grant the service
  account console access, or AppLocker blocked `uv.exe` outside `C:\dev\.uv`.
- Fix: RDP into the host as `jason`, confirm `uv --version` works, re-run
  `install.ps1 -Pull -Mode Node`. If still blocked, check Event Viewer →
  Applications and Services Logs → AppLocker.

### `uvx windows-mcp@0.7.1 --help` returns a different version

- Cause: uvx resolved a different cached wheel because UV's cache moved or
  was pruned.
- Fix: clear the cache (`Remove-Item -Recurse "$env:UV_CACHE_DIR"`) and
  re-run `install.ps1`. The probe re-installs deterministically.

### FileSystem `delete` called without approval

- This is a policy violation. The IronClaw approval engine on the WSL
  bridge must refuse the call. If it went through, file a ticket against
  the policy engine, then check the agent session log for the
  pre-violation decision.
- Rollback from `telemetry/recent-filesystem.jsonl` if the agent enabled
  audit logging.

### Upstream pushes a major version while a sprint is live

- Do not bump mid-sprint. Log the delta in `backlog/` and defer to the
  next sprint's planning window. The pin protects us from surprise
  breakage.

## References

- ADR-015 — `docs/adr/adr-015-devops-sysadmin-skill.md`
- Upstream — `~/Windows-MCP/README.md`, `SECURITY.md`, `manifest.json`
- Skill — `skills/devops-sysadmin/SKILL.md`
- Configs — `skills/devops-sysadmin/windows-mcp-config.json`,
  `windows-mcp-config.wsl.toml`
- Installers — `skills/devops-sysadmin/install.ps1`,
  `install.sh`
- Drift scripts — `skills/devops-sysadmin/scripts/check-windows-mcp-version.{ps1,sh}`
- Rollout — `skills/devops-sysadmin/runbooks/win1-rollout.md`
