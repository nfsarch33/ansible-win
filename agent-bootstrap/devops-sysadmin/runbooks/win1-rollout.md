# win1 rollout runbook — devops-sysadmin skill (v250 Sprint 2 Day 4)

Plan: `devops_ironclaw_fleet_skill_v250` task `s2-win1-rollout` (L178-L182).
ADR: `adr-015-devops-sysadmin-skill.md`, section 7 (LLM tiers) and section 8
(this runbook).

## Goal

Bring `win1` (desktop-078m990-win1) under the devops-sysadmin skill so that:

1. `uvx windows-mcp` is reachable from WSL1 over stdio, running under local
   admin `jason` (not the Tailscale identity `jaslian@...`).
2. IronClaw on WSL1 can shell into the Windows host via
   `mcp.windows-mcp.PowerShell` without opening a TCP port.
3. The `morning-drift` routine runs every day at 08:00 AEST, invoking
   `~/Code/global-kb/scripts/fleet/ansible-check.sh win1` and dropping the
   report under `session-handoffs/evidence/win1-drift-YYYYMMDD.txt`.

This runbook is the *exact* invocation path an operator follows. All commands
are read-only from the Mac/WSL1 agent side until the step flagged
`[destructive on win1]`.

## Preconditions (verify before running)

Run each check from WSL1. If any precondition fails, stop and fix before
continuing to Phase 1.

1. **win1 reachable on fleet LAN** —
   `tailscale ping --c 1 win1` should return `pong ... via DERP` or direct.
2. **SSH mesh works** (v249 firewall rule `Fleet-LAN-WIN-SSH-22` present) —
   `ssh -o BatchMode=yes jason@win1 'hostname'` should print
   `desktop-078m990-win1`.
3. **NAS packet exists** —
   `ls '/mnt/nas/scripts/devops-sysadmin/install.ps1'` (or browse in Windows
   Explorer); the file must be present.
4. **1Password service token loaded in WSL1 env** (per ADR-015 §5) —
   `op whoami` should report
   `Service Account: DevOps IronClaw Fleet`.
5. **`ansible-check.sh` wrapper committed on `main`** —
   `cd ~/Code/global-kb && git show-ref --verify refs/heads/main -- scripts/fleet/ansible-check.sh`
   should return a non-empty object id.

## Rollout plan

The rollout has three phases. Each phase is gated on the previous one.

### Phase 1 — Dry-run preflight (read-only, safe to re-run)

From WSL1, have IronClaw or the operator issue a Windows-MCP PowerShell call
that inspects the host without writing anything:

```powershell
# Runs on win1 as jason via uvx windows-mcp -> powershell.exe subprocess.
# This is the read-only half of install.ps1 -NoOp.
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
Write-Host "whoami: $($me.Name)"
if (-not ($me.Name -match 'jason$')) {
    throw "Expected local admin 'jason'; got '$($me.Name)'. Stop."
}
Get-Service sshd | Format-Table -AutoSize
Get-NetFirewallRule -DisplayName 'Fleet-LAN-WIN-SSH-22' |
    Select-Object -Property DisplayName, Enabled, Direction, Action |
    Format-Table -AutoSize
tailscale version | Select-Object -First 1
```

Acceptance: `whoami` ends in `\jason`, sshd is `Running`/`Auto`, firewall rule
is enabled, Tailscale version is `>= 1.88.0`.

If any check fails, stop here and rerun
`scripts/fleet/windows/Bootstrap-FleetNode.ps1` from the console.

### Phase 2 — install.ps1 under local admin jason [destructive on win1]

> **Identity note.** win1's Tailscale identity is `jaslian@gmail.com` but the
> *local admin* is `jason` (a per-machine Windows account). `install.ps1`
> enforces this via `Assert-LocalAdmin` and warns if the account does not end
> in `jason`.

Option A (preferred, WSL1-driven via Windows-MCP Shell):

```bash
# From WSL1, as any user; the Windows-MCP bridge will sudo via UAC prompt.
cursor-agent mcp call windows-mcp PowerShell --args '{
  "script": "Start-Process powershell.exe -Verb RunAs -ArgumentList \"-NoLogo -NonInteractive -ExecutionPolicy Bypass -File \\\"\\\\\\\\SynologyRouter\\\\filesys3\\\\scripts\\\\devops-sysadmin\\\\install.ps1\\\" -Pull -Mode Node\""
}'
```

Option B (console fallback if UAC relay over MCP is blocked by DCG or
SmartScreen): RDP/console into win1 as `jason`, open an admin PowerShell, and
run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd \\SynologyRouter\filesys3\scripts\devops-sysadmin
.\install.ps1 -Pull -Mode Node
```

Either option produces the same idempotent final state:

- `C:\dev\.uv` UV root populated (AppLocker-safe).
- `%USERPROFILE%\.ironclaw\skills\devops-sysadmin\` hydrated from the NAS.
- Windows Credential Manager holds `OP_SERVICE_ACCOUNT_TOKEN` (per-machine,
  DPAPI).
- Scheduled task `IronClaw-DevOpsSysAdmin-Preflight` registered.
- MCP client configs written to
  `%USERPROFILE%\.ironclaw\config.d\windows-mcp.json` (host-side) and to
  `$HOME/.ironclaw/config.d/windows-mcp.toml` on WSL1 (via the
  `skills/devops-sysadmin/windows-mcp-config.wsl.toml` manifest).

Verify the install completed successfully:

```powershell
# On win1 as jason
Get-ScheduledTask -TaskName 'IronClaw-DevOpsSysAdmin-Preflight' |
    Select-Object TaskName, State
uvx --from windows-mcp windows-mcp --help | Select-Object -First 1
Test-Path $env:USERPROFILE\.ironclaw\skills\devops-sysadmin\SKILL.md
```

All three must return a non-error value.

### Phase 3 — wire morning-drift and capture first evidence

1. Commit the morning-drift routine (already done in this sprint —
   `skills/devops-sysadmin/routines/morning-drift.yml`). The routine calls
   the v249 wrapper as `bash $HOME/Code/global-kb/scripts/fleet/ansible-check.sh {node}`;
   the `{node}` placeholder is substituted by the routine runner.

2. Run the drift check once manually from WSL1 to prime the evidence file:

   ```bash
   # From WSL1
   cd ~/Code/global-kb
   git pull --ff-only origin main
   mkdir -p ~/ai-agent-business-stack/session-handoffs/evidence
   bash scripts/fleet/ansible-check.sh win1 \
     | tee ~/ai-agent-business-stack/session-handoffs/evidence/win1-drift-$(date -u +%Y%m%d).txt
   ```

   Exit code 0 means no drift; exit code 2 means drift was reported but the
   assertions are non-fatal (drift is *allowed* evidence, not a broken run).
   Any other exit code is a fatal infra error (ansible or SSH).

3. Copy the first drift report into
   `session-handoffs/evidence/win1-drift-YYYYMMDD.txt`, fill in the template
   stub `win1-drift-YYYYMMDD.txt.template`, and stage it for the Sprint 2
   handoff.

4. Enable the routine in the IronClaw routine runner manifest (out of scope
   for this runbook; handled by task `s2-onboard-automation` via
   `fleet-onboard-node.sh --with-devops-skill`).

## Rollback

- `install.ps1 -Mode Workstation -NoOp` lists everything that would change.
- To fully remove the skill: delete `%USERPROFILE%\.ironclaw\skills\devops-sysadmin\`,
  `Unregister-ScheduledTask -TaskName 'IronClaw-DevOpsSysAdmin-Preflight' -Confirm:$false`,
  and `cmdkey /delete:IronClaw/OP_SERVICE_ACCOUNT_TOKEN`.
- UV, windows-mcp, and OpenSSHd installed by Bootstrap-FleetNode.ps1 are
  *kept* across rollback; they belong to the host baseline.

## Evidence this runbook was followed

Drop the following artefacts under `session-handoffs/evidence/`:

- `win1-drift-YYYYMMDD.txt` — full stdout of `ansible-check.sh win1`
- `win1-install-YYYYMMDD.log` — redirected output of `install.ps1`
- `win1-preflight-YYYYMMDD.json` — JSON result of the scheduled preflight task
- `s2-win1-rollout-report.md` — this sprint's handoff (see sibling file)
