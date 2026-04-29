#!/usr/bin/env bash
# devops-sysadmin: disk + VRAM report for nightly-audit routine.
set -uo pipefail

node="${HOST_LABEL:-$(hostname -s)}"
ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

printf '{"node":"%s","ts":"%s"' "$node" "$ts"

# disk
printf ',"disk":['
first=true
while read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$first" == true ]]; then first=false; else printf ','; fi
    read -r fs size used avail pct mount <<<"$line"
    printf '{"fs":"%s","size":"%s","used":"%s","avail":"%s","pct":"%s","mount":"%s"}' \
        "$fs" "$size" "$used" "$avail" "$pct" "$mount"
done < <(df -hP | awk 'NR>1 && $6 !~ /^\/(boot|run|snap|sys|proc|dev)/ {print}')
printf ']'

# vram (WSL with nvidia-smi accessible, or native Linux with nvidia-smi)
if command -v nvidia-smi >/dev/null 2>&1; then
    printf ',"gpus":['
    first=true
    while IFS=',' read -r idx name temp used total; do
        [[ -z "$idx" ]] && continue
        idx="${idx// /}"; temp="${temp// /}"; used="${used// /}"; total="${total// /}"
        if [[ "$first" == true ]]; then first=false; else printf ','; fi
        printf '{"index":%s,"name":"%s","temp_c":%s,"vram_used_mb":%s,"vram_total_mb":%s}' \
            "$idx" "$(echo "$name" | sed 's/"/\\"/g; s/^ *//; s/ *$//')" "$temp" "$used" "$total"
    done < <(nvidia-smi --query-gpu=index,name,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
    printf ']'
fi

printf '}\n'
