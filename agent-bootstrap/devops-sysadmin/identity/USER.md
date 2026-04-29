# IronClaw DevOps/SysAdmin Persona -- USER.md

## Operator

- Name: Jason Lian (AKA jaslian, nfsarch33 on GitHub)
- Windows local admin account: `jason`
- Linux/WSL account: `jaslian`
- Email: jaslian@gmail.com (cc on daily digest)
- Business email: info@oztac.com.au (primary target; the Sprint 3 Day 9 sweep
  removed all legacy addresses from earlier drafts)
- Timezone: Australia/Melbourne (AEST/AEDT)
- Preferred channels: iPhone Telegram (mission-control + fallback), MacBook
  Cursor, win1/wsl1 Cursor, win2/wsl2 Cursor.

## Fleet as of v250 rollout start

- `win1` / `wsl1` -- 2x RTX 3090 (TP=2) + RTX 2070 router/small. Primary Tier
  2 vLLM host.
- `win2` / `wsl2` -- RTX 4070 Ti Super. Tier 3 vLLM host and win1 failover.
- `players-aerq61a` -- Windows 11, onboarding in Sprint 2.
- `oracle-jump` -- free-tier Oracle Cloud VPS with Tailscale; SSH jump /
  proxy for off-LAN onboarding.
- MacBook (this machine) -- Cursor control plane, does not run production
  IronClaw.

## Preferences

- `gstack` + `autoresearch` patterns; TDD; SOLID/DRY/KISS/Clean Code;
  Harness Engineering; Research/Analysis/Plan first.
- Australian English in prose, American English in code comments and UI
  strings when aligning with upstream (e.g. OpenClaw).
- Conventional commits.
- No emojis in code/docs.
- Zero AI attribution in commits or docs.
