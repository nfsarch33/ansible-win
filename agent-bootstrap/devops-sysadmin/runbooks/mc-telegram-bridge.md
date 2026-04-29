# mission-control Telegram bridge runbook (v250 Sprint 3 Day 7)

Plan: `devops_ironclaw_fleet_skill_v250` task `s3-mc-telegram` (L195-L200).
ADR: `docs/adr/adr-015-devops-sysadmin-skill.md` §3 (Hybrid Telegram control plane)
and `docs/adr/adr-0003-devops-agent-architecture.md` §A2A-delegation.

## Goal

Bring `@mc_sysadmin_bot` online on the mission-control host (WSL1 by default)
so that Jason, as Telegram user `jaslian`, can drive the whole fleet with
five allow-listed commands:

| Verb | Tier | What it delegates to |
|------|------|----------------------|
| `/fleet status` | read_only | mission-control IronClaw -> `devops-sysadmin/routines/nightly-audit.yml` (fleet view) |
| `/node <name> drift` | read_only | mission-control IronClaw -> `devops-sysadmin/routines/morning-drift.yml` on the target node |
| `/node <name> restart-ironclaw` | restart | mission-control IronClaw -> per-node `scripts/restart-ironclaw.ps1` |
| `/node <name> tokens` | read_only | mission-control IronClaw -> per-node `scripts/llm-tiers-probe.sh` |
| `/report daily` | read_only | mission-control IronClaw -> `cmd/fleet-daily-report` (Sprint 3 Day 9) |

Anything else is rejected with a reason drawn from the closed enum
`{empty_allowlist, unknown_user, unknown_verb, unknown_node, extra_tokens, missing_arg, too_long, delegate_error}`
and a `mctelegram_rejects_total{reason=...}` Prometheus counter
increment. Any update from a Telegram user id NOT in the allowlist is
rejected with reason `unknown_user` and logged with a SHA-256 hash of
the sender id (never the raw id).

Every accepted command emits:

1. A Mem0 memory tagged
   `["evoloop:cycle", "skill:devops-sysadmin", "telegram:mc", "verb:<...>", "tier:<...>", "node:<...>"]`
   in `app_id=cursor-global-kb` via the shared `fleet-mc-telegram` user.
2. A `mctelegram_delegations_total{verb,node,tier}` counter increment.
3. A structured log line
   `component=mctelegram.evoloop source=mc_sysadmin_bot verb=... node=... task_id=... tier=...`
   scraped by `evoloop-daemon` so the DRL reward loop sees every
   delegation as a cycle signal.

## Preconditions

Run from the mission-control host (WSL1 unless this fleet graduated to a
dedicated host).

1. **Go module is green** —
   `cd ai-agent-business-stack/go && GOTOOLCHAIN=go1.25.6 go test ./internal/mctelegram/... ./cmd/mc-telegram-bridge/...`
2. **1Password service account signed in** —
   `op whoami` must report `Service Account: DevOps IronClaw Fleet`.
3. **Scopes file allows every field** (`skills/devops-sysadmin/op-scopes.yaml`):
   - `Telegram mc_sysadmin_bot / token`
   - `Telegram mc_sysadmin_bot / a2a_hmac`
   - `Telegram Allowlist / jaslian_user_id`
   - `Mem0 API / credential`
4. **Fleet inventory exists at the global-kb path** —
   `ls -l ~/Code/global-kb/fleet/nodes.yaml` should print a regular file.
5. **Mission-control IronClaw A2A gateway reachable** —
   `curl -fsS http://mc-ironclaw:8787/healthz` should return `ok`. If
   you are running outside the compose network, replace with the
   tailnet URL from `fleet/nodes.yaml`.
6. **evoloop compose network exists** — the bridge joins the existing
   `evoloop` and `docker_default` networks so `drl-prometheus` can
   scrape `mc-telegram-bridge:9302` without a reverse tunnel. If
   missing, start the Day 0 stack first:
   `docker compose -f docker/docker-compose.evoloop.yml up -d`.

## Run (happy path)

```bash
cd ~/ai-agent-business-stack

op inject -i docker/.env.mc-telegram.tpl > docker/.env.mc-telegram
echo "MC_TELEGRAM_A2A_ENDPOINT=http://mc-ironclaw:8787/tasks" >> docker/.env.mc-telegram
echo "MEM0_API_KEY=$(op read 'op://Cursor_IronClaw/Mem0 API/credential')" >> docker/.env.mc-telegram

docker compose --env-file docker/.env.mc-telegram \
  -f docker/docker-compose.mc-telegram.yml up -d --build

docker logs -f --tail 80 mc-telegram-bridge
```

Healthy startup prints:

- `mc-telegram-bridge starting ... allowed_user_count=1`
- `fleet inventory loaded known_nodes=<>3>`
- `telegram long-poll: starting` (from the daemon)

Verify from the MacBook:

```bash
curl -fsS http://mc-ironclaw:9302/healthz
curl -fsS http://mc-ironclaw:9302/metrics | rg mctelegram_ | head -20
```

Send a live probe from Telegram as `jaslian`:

```
/fleet status
```

Expected:

1. The bridge logs
   `delegated command ... verb=fleet.status task_id=... tier=read_only`.
2. Prometheus shows `mctelegram_delegations_total{verb="fleet.status",node="fleet",tier="read_only"} 1`.
3. Mem0 (fleet-mc-telegram user) has a new memory tagged
   `["evoloop:cycle", "skill:devops-sysadmin", "telegram:mc", "verb:fleet.status", ...]`.
4. Telegram replies with the A2A response rendered by the IronClaw
   gateway (queued / result summary).

## Reject path (must stay hot)

Every Sprint 3 Day 7 acceptance run includes a red-team probe:

1. From any non-allowlisted Telegram user, send `/fleet status`. The
   bridge MUST silently reject (no outbound reply, so attackers cannot
   confirm bot presence) and increment
   `mctelegram_rejects_total{reason="unknown_user"}`.
2. From `jaslian`, send `/fleet explode`. The bridge MUST reply with
   `unknown command. try /fleet status, /node <name> drift|restart-ironclaw|tokens, or /report daily`
   and increment `mctelegram_rejects_total{reason="unknown_verb"}`.
3. From `jaslian`, send `/node unknown-host drift`. The bridge MUST
   reply with `unknown node. check fleet/nodes.yaml` and
   increment `mctelegram_rejects_total{reason="unknown_node"}`.

All three events MUST log at `WARN` with a SHA-256 hash of the sender id
(never the raw id) and MUST persist a reject memory in Mem0 tagged
`telegram:mc:reject`.

## Disable / rollback

Stop the bridge, rotate the token, and confirm the A2A gateway is idle:

```bash
docker compose -f docker/docker-compose.mc-telegram.yml down
op item edit 'Telegram mc_sysadmin_bot' token=$(openssl rand -hex 32)
curl -fsS http://mc-ironclaw:8787/tasks | jq '.queued_from_telegram // 0'
```

The telegram-health routine (`skills/devops-sysadmin/routines/telegram-health.yml`)
will detect the outage within 3 minutes and promote each node's emergency
fallback bot for 30 minutes. Sprint 3 Day 8 (`s3-fallback-bots`) owns
that promotion end-to-end.

## Evidence (save under session-handoffs/evidence)

- `s3-mc-telegram-report.md` — what ran, TDD output, live probe proofs.
- Screenshots or text captures of the three reject classes + one
  happy-path delegation.
- `mctelegram_delegations_total` + `mctelegram_rejects_total` Prometheus
  counter snapshot (`curl http://mc-ironclaw:9302/metrics`).

## Follow-ups tracked in the plan

- Sprint 3 Day 8 `s3-fallback-bots`: per-node fallback bots, 24 h token
  rotation, and `telegram-health` promotion demo.
- Sprint 3 Day 9 `s3-daily-report`: hook `/report daily` into
  `cmd/fleet-daily-report` + email delivery via SMTP2GO/Resend/Brevo.
- Sprint 5 Day 13 `s5-slo-adr`: SLO for Telegram round-trip latency.
