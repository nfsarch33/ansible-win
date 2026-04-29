#!/usr/bin/env bash
# Check the installed `uvx windows-mcp` version against the devops-sysadmin
# pin and emit a Prometheus textfile metric. WSL1-first; optional on macOS.
#
# Usage: check-windows-mcp-version.sh [--quiet]
# Exits 0 when drift=0, 1 when drift detected, 2 when telemetry missing.

set -uo pipefail

QUIET=false
for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
    esac
done

log() {
    if [[ "$QUIET" != true ]]; then
        printf '%s\n' "$*"
    fi
}

SKILL_DIR_DEFAULT="${HOME}/.cursor/skills/ironclaw-win-sysadmin"
SKILL_DIR="${IRONCLAW_SKILL_DIR:-$SKILL_DIR_DEFAULT}"
if [[ ! -d "$SKILL_DIR" ]]; then
    SKILL_DIR="${HOME}/.ironclaw/skills/devops-sysadmin"
fi

TELEM_DIR="${SKILL_DIR}/telemetry"
VERSION_FILE="${TELEM_DIR}/windows-mcp.version"
PROM_FILE="${TELEM_DIR}/windows-mcp-drift.prom"
NODE="${HOST_LABEL:-$(hostname -s)}"

mkdir -p "$TELEM_DIR"

if [[ ! -s "$VERSION_FILE" ]]; then
    log "telemetry missing or empty: $VERSION_FILE -- run install.sh first"
    cat >"$PROM_FILE" <<EOF
# HELP windows_mcp_version_pin Pinned windows-mcp version (1 = tracked)
# TYPE windows_mcp_version_pin gauge
windows_mcp_version_pin{node="${NODE}",pin="unknown"} 0
# HELP windows_mcp_drift Drift status for windows-mcp pin (0 = clean, 1 = drift)
# TYPE windows_mcp_drift gauge
windows_mcp_drift{node="${NODE}",pin="unknown",reason="missing"} 1
EOF
    exit 2
fi

PINNED="$(tr -d '[:space:]' <"$VERSION_FILE")"
if [[ -z "$PINNED" ]]; then
    log "pin file empty: $VERSION_FILE"
    exit 2
fi
SPEC="windows-mcp@${PINNED}"

DRIFT=0
REASON="ok"

# WSL1 path: probe via PowerShell. Non-WSL hosts skip the live probe and rely
# on the pin record alone.
if grep -qi microsoft /proc/version 2>/dev/null; then
    if command -v powershell.exe >/dev/null 2>&1; then
        if ! powershell.exe -NoLogo -NonInteractive -Command "uvx ${SPEC} --help" >/dev/null 2>&1; then
            DRIFT=1
            REASON="uvx-failed"
        fi
    else
        DRIFT=1
        REASON="powershell-missing"
    fi
fi

cat >"$PROM_FILE" <<EOF
# HELP windows_mcp_version_pin Pinned windows-mcp version (1 = tracked)
# TYPE windows_mcp_version_pin gauge
windows_mcp_version_pin{node="${NODE}",pin="${PINNED}"} 1
# HELP windows_mcp_drift Drift status for windows-mcp pin (0 = clean, 1 = drift)
# TYPE windows_mcp_drift gauge
windows_mcp_drift{node="${NODE}",pin="${PINNED}",reason="${REASON}"} ${DRIFT}
EOF

log "node=${NODE} pin=${PINNED} drift=${DRIFT} reason=${REASON}"
exit $DRIFT
