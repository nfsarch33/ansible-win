#!/usr/bin/env bash
# devops-sysadmin: mission-control Telegram liveness streak counter.
#
# Usage: mc-streak.sh --update <true|false|1|0|ok|fail>
# Stores state at ~/.ironclaw/skills/devops-sysadmin/telemetry/mc-streak.state.
set -euo pipefail

state_dir="${HOME}/.ironclaw/skills/devops-sysadmin/telemetry"
mkdir -p "$state_dir"
state_file="${state_dir}/mc-streak.state"

if [[ $# -lt 2 || "$1" != "--update" ]]; then
    echo "usage: mc-streak.sh --update <ok|fail>" >&2
    exit 64
fi

val="${2,,}"
ok=0
case "$val" in
    true|1|ok|yes) ok=1 ;;
    *) ok=0 ;;
esac

prev=0
if [[ -f "$state_file" ]]; then
    prev="$(cat "$state_file" 2>/dev/null || echo 0)"
fi

if [[ "$ok" -eq 1 ]]; then
    echo 0 > "$state_file"
else
    next=$(( prev + 1 ))
    echo "$next" > "$state_file"
fi

cat "$state_file"
