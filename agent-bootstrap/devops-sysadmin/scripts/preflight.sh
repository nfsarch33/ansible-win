#!/usr/bin/env bash
# devops-sysadmin preflight check (WSL + macOS).
#
# Gates:
#   - host is in fleet/nodes.yaml (checked against $HOST_LABEL env or hostname)
#   - mem0 ping (app_id=cursor-global-kb)
#   - evoloop-daemon :9301/healthz
#   - windows-mcp bridge (only on WSL)
#   - disk free > 10%
#   - op whoami (best-effort)
#
# Exits 0 on green, 1 on any gate failure (except optional gates which only warn).

set -uo pipefail

VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true; shift ;;
        *) shift ;;
    esac
done

log() {
    if [[ "$VERBOSE" == true ]]; then
        printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
    fi
}

warn() { printf 'WARN: %s\n' "$*" >&2; }
err()  { printf 'ERR:  %s\n' "$*" >&2; }

fail=0

# --- host in fleet ---
NODE_LABEL="${HOST_LABEL:-$(hostname -s)}"
FLEET_FILE="${HOME}/Code/global-kb/fleet/nodes.yaml"
if [[ ! -f "$FLEET_FILE" ]]; then
    FLEET_FILE="${HOME}/ai-agent-business-stack/fleet/nodes.yaml"
fi
if [[ -f "$FLEET_FILE" ]] && ! grep -qE "^\s*-?\s*name:\s*\"?${NODE_LABEL}\"?" "$FLEET_FILE"; then
    warn "node '${NODE_LABEL}' not in ${FLEET_FILE}; ok for Cursor MacBook, fleet nodes must register"
fi

# --- disk ---
read -r disk_used_pct <<<"$(df -P "$HOME" | awk 'NR==2 {gsub("%","",$5); print $5}')"
if [[ -n "$disk_used_pct" && "$disk_used_pct" -ge 90 ]]; then
    err "disk usage at ${disk_used_pct}% on $HOME"
    fail=1
else
    log "disk usage ${disk_used_pct:-?}%"
fi

# --- evoloop-daemon reachability ---
if command -v curl >/dev/null 2>&1; then
    if curl -fsS -m 3 http://127.0.0.1:9301/healthz >/dev/null 2>&1; then
        log "evoloop-daemon healthz OK"
    else
        warn "evoloop-daemon :9301/healthz unreachable"
    fi
fi

# --- mem0 ping ---
if command -v mem0 >/dev/null 2>&1; then
    if mem0 ping --app_id cursor-global-kb >/dev/null 2>&1; then
        log "mem0 ping OK"
    else
        warn "mem0 ping failed"
    fi
fi

# --- windows-mcp bridge (WSL only) + drift check ---
if grep -qi microsoft /proc/version 2>/dev/null; then
    SKILL_DIR_LOCAL="${HOME}/.cursor/skills/ironclaw-win-sysadmin"
    if [[ ! -d "$SKILL_DIR_LOCAL" ]]; then
        SKILL_DIR_LOCAL="${HOME}/.ironclaw/skills/devops-sysadmin"
    fi
    pinned_version=""
    if [[ -s "${SKILL_DIR_LOCAL}/telemetry/windows-mcp.version" ]]; then
        pinned_version="$(tr -d '[:space:]' <"${SKILL_DIR_LOCAL}/telemetry/windows-mcp.version")"
    fi
    spec="${pinned_version:+windows-mcp@${pinned_version}}"
    spec="${spec:-windows-mcp}"
    if command -v powershell.exe >/dev/null 2>&1; then
        if powershell.exe -NoLogo -NonInteractive -Command "uvx ${spec} --help" >/dev/null 2>&1; then
            log "windows-mcp wslbridge OK (spec=${spec})"
        else
            warn "windows-mcp wslbridge failed (spec=${spec})"
        fi
    else
        warn "powershell.exe missing on WSL PATH"
    fi
    drift_script="${SKILL_DIR_LOCAL}/scripts/check-windows-mcp-version.sh"
    if [[ -x "$drift_script" ]]; then
        if ! "$drift_script" --quiet >/dev/null 2>&1; then
            warn "windows-mcp drift detected (see telemetry/windows-mcp-drift.prom)"
            fail=1
        else
            log "windows-mcp drift OK"
        fi
    fi
fi

# --- op whoami ---
if command -v op >/dev/null 2>&1; then
    if op whoami >/dev/null 2>&1; then
        log "op whoami OK"
    else
        warn "op not signed in; export OP_SERVICE_ACCOUNT_TOKEN"
    fi
fi

if [[ "$fail" -ne 0 ]]; then
    err "preflight failed"
    exit 1
fi

log "preflight OK"
exit 0
