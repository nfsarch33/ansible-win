---
name: devops-sysadmin
version: 0.1.0
summary: DevOps/SysAdmin IronClaw persona for every Windows 11 fleet node. Windows-MCP stdio bridge, 1Password service-account secrets, MiniMax + local-vLLM tier routing, Ansible day-2 drift, hybrid Telegram control, EvoLoop-DRL participation, resource-aware guardrails. Composes existing skills; does not duplicate.
triggers:
  - devops-sysadmin
  - ironclaw fleet agent
  - fleet onboard
  - windows-mcp
  - ansible drift
  - telegram mission-control
  - vllm tier routing
  - evoloop cycle
  - fleet node install
  - minimax tier1
required_tools:
  - powershell
  - uvx
  - op
  - ssh
  - docker
  - ansible-playbook
  - go
untrusted_operation_ceiling: read_only
approval_rules:
  auto:
    - read-only queries
    - container start/stop (non-DRL)
    - file edits under workspace
    - terraform plan
    - ansible --check --diff
  telegram_approval:
    - firewall changes
    - SSH key install/rotate
    - docker volume rm/prune
    - terraform apply
    - ansible without --check on service-affecting playbooks
    - systemctl disable/stop critical services
  blocked:
    - rm -rf on system paths
    - mkfs on mounted filesystems
    - dd on block devices
    - direct edits to /mnt/c from WSL
owners:
  - jason.lian
links:
  adr:
    - docs/adr/adr-015-devops-sysadmin-skill.md
    - docs/adr/adr-0003-devops-agent-architecture.md
  guardrails:
    - cursor-config/rules/devops-agent-guardrails.md
  peers:
    - skills/devops-fleet-admin/SKILL.md
    - ~/.cursor/skills/ironclaw-mission-control/SKILL.md
    - ~/.cursor/skills/ironclaw-multi-agent/SKILL.md
    - ~/.cursor/skills/ironclaw-evolver/SKILL.md
---

# DevOps/SysAdmin IronClaw Skill (v250)

Fleet DevOps operator skill that runs on every Windows 11 fleet node's
IronClaw instance and on MacBook/WSL Cursor. Canonical source at
`ai-agent-business-stack/skills/devops-sysadmin/`; symlinked to Cursor
activation path `~/.cursor/skills/ironclaw-win-sysadmin/`; rsynced to the NAS
bundle `\\SynologyRouter\filesys3\scripts\devops-sysadmin\`; materialised on
each node at `%USERPROFILE%\.ironclaw\skills\devops-sysadmin\` by `install.ps1`.

Read `docs/adr/adr-015-devops-sysadmin-skill.md` before changing this skill.

## Purpose

Provide a single named playbook on every fleet node that:

1. Exposes Windows and Linux/WSL host control via Windows-MCP stdio.
2. Pulls secrets read-only via a 1Password service account.
3. Routes LLM traffic through `llm-cluster-router` (Tier 1 MiniMax, Tier 2-3
   local vLLM on win1/win2), falling back by resource guardrails.
4. Runs Ansible day-2 drift detection as a morning routine.
5. Accepts commands from iPhone Telegram via mission-control + A2A, or the
   per-node emergency fallback bot when mission-control is down.
6. Writes every cycle to Mem0 under `app_id=cursor-global-kb` so EvoLoop-DRL
   can share fleet patterns.
7. Self-heals degraded services (restart stuck IronClaw, rotate keys, switch
   LLM tier) without asking approval for read-only + restart + rotate actions.

## Preflight

Before any non-read-only operation, verify:

1. Host is in `fleet/nodes.yaml`; operator identity is `jaslian`.
2. Working dir is a known fleet root (not `/mnt/c/`).
3. Docker context is `default` on WSL1 / `desktop-windows` on Windows host.
4. `op whoami` returns the fleet service account.
5. `mem0 ping --app_id cursor-global-kb` succeeds.
6. `/metrics` on port 9301 (EvoLoop daemon) responds on WSL1.
7. Host free disk > 10%; GPU VRAM < 90%; GPU temp < 85C.

Run `skills/devops-sysadmin/scripts/preflight.sh` or the PowerShell
equivalent `preflight.ps1` and abort the operation if any gate fails.

## Windows host setup

Run the idempotent installer as local admin `jason` (not the Tailscale
identity `jaslian@`):

```powershell
# from NAS, as local admin 'jason'
Set-Location \\SynologyRouter\filesys3\scripts\devops-sysadmin\
.\install.ps1 -Pull -Mode Node
```

What it does (idempotent):

1. Ensures `uv` is present with cache + python install dir under `C:\dev\.uv`
   (AppLocker-safe; `UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR`,
   `UV_PROJECT_ENVIRONMENT`).
2. `uvx windows-mcp --help` bootstraps the MCP server binary into that
   AppLocker-safe location; records the SHA256 in `telemetry/windows-mcp.sha`.
3. Copies the skill bundle to `%USERPROFILE%\.ironclaw\skills\devops-sysadmin\`.
4. Writes `%USERPROFILE%\.ironclaw\config.d\windows-mcp.toml` and
   `config.d\op-service-account.toml`.
5. Registers `OP_SERVICE_ACCOUNT_TOKEN` in Windows Credential Manager (per-machine,
   DPAPI-protected cache) so IronClaw can fetch it without a plaintext env var.
6. Adds a scheduled task `IronClaw-Preflight` that runs `preflight.ps1` at
   boot + every 3 min (feeds `telemetry/prom-rules.yml`).

## WSL setup

Run on WSL1 (and on MacBook Cursor-side, same command is safe):

```bash
bash skills/devops-sysadmin/install.sh
```

What it does (idempotent):

1. Ensures `op` CLI is installed (`apt install` or Homebrew fallback).
2. Configures `powershell.exe -Command "uvx windows-mcp"` bridge; records
   the reachable tool surface via `windows-mcp --help | tee telemetry/wslbridge.txt`.
3. Symlinks `~/.cursor/skills/ironclaw-win-sysadmin` -> canonical
   (idempotent: does nothing if already correct).
4. Validates Mem0 + MiniMax creds via `op read` without logging them.
5. Installs a `user@1000.service`-scoped `systemd --user` unit
   `ironclaw-preflight.service` that runs every 3 min.

## Windows-MCP wiring

Primary bridge is `stdio`. We do not expose Windows-MCP over TCP / SSE on the
LAN even behind Tailscale; the agent always dials `uvx windows-mcp` as a
subprocess.

Tool surface used by this skill (canonical names from upstream Windows-MCP,
no fork):

- Read-only: `App` (read), `Process` (list mode), `Screenshot`, `Snapshot`,
  `Clipboard` (read), `Registry` (get/list mode).
- Control: `PowerShell`, `Click`, `Type`, `Scroll`, `Move`, `Shortcut`,
  `Wait`, `MultiSelect`, `MultiEdit`, `Clipboard` (write), `Notification`,
  `Registry` (set/delete, **gated**), `Scrape` (browser), `App` (launch/resize/switch),
  `Process` (kill, **gated**).

Client config excerpts live in `windows-mcp-config.json` (Windows host) and
`windows-mcp-config.wsl.toml` (WSL bridge). They set:

- `ANONYMIZED_TELEMETRY=false`
- `WINDOWS_MCP_SCREENSHOT_SCALE=0.5` (works under Claude Desktop 1 MB cap)
- `UV_CACHE_DIR=C:/dev/.uv/cache` (AppLocker-safe)

## 1Password service-account wiring

`op-scopes.yaml` enumerates the read-only item paths this skill is allowed to
read. Write-scopes are explicitly **empty** for this skill; rotation jobs have
their own scoped service accounts.

Smoke test:

```powershell
op read "op://Cursor_IronClaw/MiniMax M2.7 highspeed API 1/credential" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "op smoke failed" }
```

Never log the credential value. The `install.ps1` smoke test prints only the
SHA-256 prefix + byte length and compares against a fingerprint saved in
`telemetry/minimax-credential.fingerprint`.

## LLM tier routing (MiniMax + local vLLM)

Uses existing `llm-cluster-router` config (plus one additive tier file):

| Tier | Target | When |
|------|--------|------|
| 1 | MiniMax `M2.7-highspeed` (cloud) | Planning, summarisation, small prompts; under $5/day CostGuard |
| 2 | win1 vLLM (2x RTX 3090 TP=2 + RTX 2070 router/small) | Larger context, offline, VRAM budget < 85% |
| 3 | win2 vLLM (RTX 4070 Ti Super) | Fallback to Tier 2 when win1 saturated or offline |
| 4 | CPU (llama.cpp on WSL) | Last-ditch local; degrades gracefully |

Resource-aware routing inputs (from Prometheus, scraped via
`telemetry/prom-rules.yml`):

- `ironclaw_devops_gpu_vram_used_bytes / ironclaw_devops_gpu_vram_total_bytes`
- `windows_physical_memory_used_bytes`
- `windows_free_disk_bytes`
- `llm_cluster_router_tier_latency_seconds_p95`

MiniMax name-drift note: v249 evidence recorded `MiniMax-M2`; the v250 plan
targets `MiniMax-M2.7-highspeed`. The router config under `llm-cluster-router`
names the model `MiniMax-M2.7-highspeed` and keeps an alias `MiniMax-M2` for
back-compat logs; see `docs/adr/adr-015-devops-sysadmin-skill.md` + the
Sprint 1 Day 3 handoff for the naming-drift record.

## Resource awareness

Always-on guardrails. Abort the planned op and emit an EvoLoop incident if any
of:

- Any GPU temp > 85C for > 30s.
- Any GPU VRAM > 90% before starting a local inference job.
- Free disk on the target mount < 10%.
- Paid API daily spend > $5 (CostGuard).
- Skill activation has been >= 50% of prompts in the last hour (signal noise).

Prometheus rules in `telemetry/prom-rules.yml` publish the alerts; the IronClaw
orchestrator consumes them and pauses tier-2/3 jobs proactively.

## Ansible day-2 drift hook

`routines/morning-drift.yml` invokes:

```bash
bash ~/Code/global-kb/scripts/fleet/ansible-check.sh --host win1
```

The wrapper (ADR-014) runs `ansible-playbook --check --diff -i
ansible/inventory/fleet.yml ansible/playbooks/win1-drift-check.yml` and exits 0
iff zero drift. Drift report is saved to
`session-handoffs/evidence/<node>-drift-YYYYMMDD.txt` and a summary is pushed
to Mem0 tag `ansible:drift`.

## Telegram hybrid control

Default (mission-control primary):

- iPhone -> `@mc_sysadmin_bot` -> mission-control IronClaw on WSL1 -> A2A
  delegate to the per-node `devops-sysadmin` (`routines/mc-delegate.yml`).
- Only `jaslian` Telegram user id is allowlisted; others receive a polite
  rejection + are logged to `telemetry/telegram-reject.jsonl`.

Fallback (per-node emergency):

- `routines/telegram-health.yml` polls mission-control every 3 min; after 3
  consecutive failures, the per-node fallback bot (`@<node>_sysadmin_fallback_bot`)
  is activated for 30 min. Bot token is rotated every 24h via 1Password by
  `routines/fallback-token-rotate.yml`.
- Fallback scope: **read-only + restart-ironclaw + evoloop status**. No
  destructive ops. Any destructive request is logged + dropped.

## EvoLoop-DRL participation

Every skill activation (start, success, failure, self-heal) emits a cycle to
the publisher stack:

- Mem0 write under `app_id=cursor-global-kb` with tags
  `evoloop:cycle`, `skill:devops-sysadmin`, `node:<name>`.
- Append to `~/Code/global-kb/global-memories/evoloop-cycles-YYYY-MM-DD.ndjson`.
- Prometheus: `evoloop_cycles_total{skill="devops-sysadmin",outcome=...}`.

The day-0 EvoLoop daemon on WSL1 is the central emitter (metrics on
`:9301/metrics`); per-node IronClaws forward their local cycles to that daemon
via the A2A gateway.

## Self-healing

Self-heal matrix (no approval required for these three):

| Symptom | Action | Notify |
|---------|--------|--------|
| IronClaw process not responding on node | Restart `ironclaw.service` / Windows Service / compose | Mem0 incident + Telegram digest |
| Paid API 429/402 burst | Rotate notify key via `InstrumentedRetrier` | Mem0 + daily digest |
| Local vLLM OOM | Switch router to next tier, set VRAM budget lower | Mem0 + Prometheus alert |

Anything beyond those asks mission-control Telegram for approval.

## Handoff

On exit, write a handoff note:

- Location: `~/Code/global-kb/global-memories/session-handoff-<date>-<node>-devops-sysadmin.md`
- Mem0 signal: `devops-sysadmin-handoff` with last KPIs + open follow-ups.

## Runbook links

- `docs/adr/adr-015-devops-sysadmin-skill.md`
- `docs/adr/adr-0003-devops-agent-architecture.md`
- `docs/adr/adr-014-ansible-day2-fleet-drift.md` (kb)
- `skills/devops-fleet-admin/SKILL.md`
- `skills/devops-sysadmin/op-scopes.yaml`
- `skills/devops-sysadmin/telemetry/prom-rules.yml`
- `skills/devops-sysadmin/routines/*.yml`

## Complementary skills (activate alongside)

`devops-fleet-admin`, `ironclaw-mission-control`, `ironclaw-multi-agent`,
`ironclaw-deploy-ops`, `ironclaw-external-ops`, `ironclaw-evolver`,
`ironclaw-ceo-agent`, `ironclaw-orchestrator`, `ironclaw-vllm`,
`ironclaw-agent-dashboard`, `llm-cluster-router`, `llm-model-evaluator`,
`wsl-gpu-ops`, `multi-gpu-inference`, `cluster-monitoring`,
`monitoring-observability`, `tailscale-fleet`, `automation-workflows`,
`memory-and-kb`, `memory-hygiene`, `agent-observability`, `docker-ops`,
`homelab-k3s`, `autonomous-research`, `aris-research-integration`.
