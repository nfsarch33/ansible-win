# Per-node Telegram fallback bridge runbook (v250 Sprint 3 Day 8)

Plan: `devops_ironclaw_fleet_skill_v250` task `s3-fallback-bots` (L199-L201).
Design: `reports/research/mc-telegram-fallback-2026-05-08.md`.
ADR: `docs/adr/adr-015-devops-sysadmin-skill.md` §3 (Hybrid Telegram
control plane).

## Goal

Bring a DORMANT per-node emergency Telegram bot online so that, if
`@mc_sysadmin_bot` goes dark for at least 90s (three consecutive mission-
control probe failures at the default 30s interval), Jason (allowlisted
as `jaslian`) can drive a narrow incident-response lane from an iPhone
without touching mission-control:

| Verb                | Tier        | Local effect |
|---------------------|-------------|--------------|
| `/status`           | `read_only` | Runs `FALLBACK_STATUS_CMD` (platform default: `systemctl is-active ironclaw` on Linux, `sc query ironclaw` on Windows, `launchctl list ai.ironclaw` on macOS). |
| `/restart-ironclaw` | `restart`   | Runs `FALLBACK_RESTART_CMD` (platform default: `systemctl restart ironclaw` / `sc restart ironclaw` / `launchctl kickstart -k gui/ai.ironclaw`). |
| `/evoloop status`   | `read_only` | HTTP GET against `FALLBACK_EVOLOOP_HEALTH_URL` (default `http://evoloop-daemon:9301/healthz`). |

Anything else is rejected with reason from the closed enum
`{empty_allowlist, unknown_user, unknown_verb, extra_tokens, missing_arg,
too_long, mc_healthy, tier_denied}` and increments
`fallbackbot_rejects_total{reason=...,node=<node>}`.

**Silent rejection is part of the contract.** The bot never emits an
outbound reply for `unknown_user` or `mc_healthy` so a probe cannot
confirm the bot is online. The ability to run anything at all is a
side effect of the gate being armed, which only happens after the mc
probe streak has exceeded `FALLBACK_MC_STREAK_THRESHOLD` (default 3).

## Preconditions

Run once per node (win1, mac1, ubuntu1). All commands assume the node
is already joined to the Tailscale fleet and can reach
`mc-ironclaw:9302`.

1. **Go module is green** (builds and tests run fine from any host):
   ```bash
   cd ai-agent-business-stack/go
   GOTOOLCHAIN=go1.25.6 go test ./internal/fallbackbot/... ./cmd/fallback-telegram-bridge/...
   ```
2. **1Password service account signed in on the node**:
   `op whoami` must report `Service Account: DevOps IronClaw Fleet`.
3. **Scopes file whitelists the per-node items**
   (`skills/devops-sysadmin/op-scopes.yaml`):
   - `Cursor_IronClaw / Telegram <node>_sysadmin_fallback_bot / token`
     (e.g. `Telegram win1_sysadmin_fallback_bot`)
   - `Cursor_IronClaw / Telegram Allowlist / jaslian_user_id`
4. **Mission-control bridge reachable from the node**:
   `curl -fsS http://mc-ironclaw:9302/healthz` should return `ok`.
   If it cannot, the gate will arm within
   `FALLBACK_MC_STREAK_THRESHOLD * FALLBACK_MC_PROBE_INTERVAL` seconds
   (90s with defaults) once the bridge is up; that is the intended
   state during a real outage.
5. **Audit volume exists** on the host:
   ```bash
   sudo install -d -m 0750 -o 10012 -g 10012 /var/log/ironclaw
   ```
   On Windows, create `C:\ProgramData\ironclaw` with equivalent ACLs.

## Run (happy path)

```bash
cd ~/ai-agent-business-stack

export FALLBACK_NODE=win1
export FALLBACK_OP_REF="op://Cursor_IronClaw/Telegram ${FALLBACK_NODE}_sysadmin_fallback_bot/token"
export FALLBACK_MC_HEALTH_URL="http://mc-ironclaw:9302/healthz"

op inject -i docker/.env.fallback-telegram.tpl \
  > docker/.env.fallback-telegram.${FALLBACK_NODE}

docker compose \
  --env-file docker/.env.fallback-telegram.${FALLBACK_NODE} \
  -f docker/docker-compose.fallback-telegram.yml up -d --build

docker logs -f --tail 80 fallback-telegram-bridge-${FALLBACK_NODE}
```

Healthy startup prints:

- `fallback-telegram-bridge starting ... allowed_user_count=1 streak_threshold=3 ...`
- `daemon: starting long poll`
- `gate watcher: mc healthy, staying dormant`

`fallbackbot_state{node="win1"}` Prometheus gauge is `0` (dormant),
`fallbackbot_mc_probe_latency_seconds` samples are flowing, and
`/healthz` returns 200.

## Arming the gate (simulated outage)

From the mission-control host, drop the `mc-ironclaw` container and
watch the node's bridge arm itself:

```bash
docker compose -f docker/docker-compose.mc-telegram.yml stop mc-telegram-bridge
```

After `3 * 30s = 90s` the node logs:

```
gate watcher: mc unhealthy, streak=3 threshold=3, promoting gate ttl=30m
```

`fallbackbot_state{node="win1"}` flips to `1` (armed). From Telegram,
sending `/status` as `jaslian` now returns the output of the platform
restart command; sending `/evoloop status` returns the local evoloop
daemon's `/healthz` summary. After the TTL elapses (default 30m) the
gate demotes even if `mc-ironclaw` is still down, forcing the
operator to wait for the next probe failure window. This is a
deliberate brake: the fallback is not meant to replace mission-
control long-term.

Once `mc-telegram-bridge` is brought back:

```bash
docker compose -f docker/docker-compose.mc-telegram.yml start mc-telegram-bridge
```

The gate watcher logs `mc healthy, demoting gate` at the next tick and
the gauge flips back to dormant.

## Reject path (must stay hot)

1. From any non-allowlisted Telegram user, send `/status`. The bridge
   MUST silently drop and increment
   `fallbackbot_rejects_total{reason="unknown_user",node="win1"}`.
2. From `jaslian` while mc is healthy, send `/status`. The bridge MUST
   silently drop and increment
   `fallbackbot_rejects_total{reason="mc_healthy",node="win1"}`.
3. From `jaslian` while gate is armed, send `/explode`. The bridge
   MUST reply with `unknown verb. try /status, /restart-ironclaw, /evoloop status`
   and increment
   `fallbackbot_rejects_total{reason="unknown_verb",node="win1"}`.

All three events MUST append an entry to
`/var/log/ironclaw/fallback-win1.ndjson` with a SHA-256 prefix of the
sender id (never the raw id), a monotonic timestamp, and the reject
reason.

## 24h token rotation

Rotation is driven by the daemon itself (no external cron) using the
host `op` binary bind-mounted into the container:

- Every `FALLBACK_ROTATE_INTERVAL` (default 24h), the `Rotator`
  executes `FALLBACK_ROTATE_HOOK` if set (typically a wrapper around
  `op item edit`) and then `op read FALLBACK_OP_REF` to pick up the
  new value.
- Failure is fail-open: the daemon retains the last known good token
  and increments
  `fallbackbot_token_rotations_total{result="failed",node="win1"}`.
  The next tick retries.
- The operator may force a rotation at any time with:
  ```bash
  docker exec fallback-telegram-bridge-win1 kill -SIGUSR1 1   # reserved; not yet wired
  ```
  Until SIGUSR1 is wired up, force rotation by running
  `op item edit` on the host item -- the Rotator picks up the new
  value at the next tick (up to `FALLBACK_ROTATE_INTERVAL / 4` wait
  in the worst case).

## Disable / rollback

```bash
docker compose \
  --env-file docker/.env.fallback-telegram.${FALLBACK_NODE} \
  -f docker/docker-compose.fallback-telegram.yml down
op item edit "Telegram ${FALLBACK_NODE}_sysadmin_fallback_bot" token=$(openssl rand -hex 32)
```

## Evidence (save under session-handoffs/evidence)

- `s3-fallback-bots-report.md` — what ran, TDD output, live probe proofs.
- `curl http://127.0.0.1:9312/metrics` snapshot showing the armed and
  dormant states for each node.
- NDJSON tail from `/var/log/ironclaw/fallback-<node>.ndjson` showing
  at least one accepted and one rejected command per class.

## Follow-ups tracked in the plan

- Sprint 3 Day 9 `s3-daily-report`: include fallback arm events in the
  daily digest so a silent incident is still visible.
- Sprint 5 Day 13 `s5-slo-adr`: fold fallback arm latency into the
  fleet SLO set.
- Sprint 5 Day 13 `s5-slo-watcher`: wire `fallbackbot_state` into the
  Prometheus alert tail so armed > 15 min raises Mem0 incident.
