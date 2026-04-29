#!/usr/bin/env bash
# Idempotent installer for the devops-sysadmin IronClaw skill on WSL (and on
# macOS Cursor-side for activation symlink).
#
# Safe to re-run; every step is guarded.

set -euo pipefail

SKILL_NAME="devops-sysadmin"
CANON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_SKILL_DIR="${HOME}/.cursor/skills/ironclaw-win-sysadmin"
RUNTIME_DIR="${HOME}/.ironclaw/skills/${SKILL_NAME}"
WINDOWS_MCP_VERSION="${WINDOWS_MCP_VERSION:-0.7.1}"
WINDOWS_MCP_SPEC="windows-mcp@${WINDOWS_MCP_VERSION}"
IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then IS_WSL=true; fi

log() { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

require() {
    local bin="$1"
    if ! command -v "$bin" >/dev/null 2>&1; then
        log "missing binary: $bin"
        return 1
    fi
}

# ---------- 1. op CLI ----------
if ! command -v op >/dev/null 2>&1; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
        if command -v brew >/dev/null 2>&1; then
            log "installing 1Password op CLI via Homebrew"
            brew install --cask 1password-cli >/dev/null
        else
            log "Homebrew not found; install op CLI manually: https://developer.1password.com/docs/cli/get-started/"
        fi
    else
        # Debian/Ubuntu
        log "installing 1Password op CLI via apt"
        if [[ ! -f /etc/apt/sources.list.d/1password.list ]]; then
            sudo install -d -m 0755 /etc/apt/keyrings
            curl -sS https://downloads.1password.com/linux/keys/1password.asc |
                sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/1password-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" |
                sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
            sudo install -d -m 0755 /etc/debsig/policies/AC2D62742012EA22
            curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol |
                sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
            sudo install -d -m 0755 /usr/share/debsig/keyrings/AC2D62742012EA22
            curl -sS https://downloads.1password.com/linux/keys/1password.asc |
                sudo gpg --dearmor --batch --yes -o /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
        fi
        sudo apt-get update -q
        sudo apt-get install -y 1password-cli
    fi
else
    log "op already installed: $(op --version 2>/dev/null || echo unknown)"
fi

# ---------- 2. Windows-MCP bridge probe (WSL only, pinned) ----------
if $IS_WSL; then
    log "probing powershell.exe -> uvx ${WINDOWS_MCP_SPEC}"
    mkdir -p "${CANON_DIR}/telemetry"
    if command -v powershell.exe >/dev/null 2>&1; then
        if powershell.exe -NoLogo -NonInteractive -Command "uvx ${WINDOWS_MCP_SPEC} --help" >"${CANON_DIR}/telemetry/wslbridge.txt" 2>&1; then
            log "wslbridge probe OK -> telemetry/wslbridge.txt (version=${WINDOWS_MCP_VERSION})"
            printf '%s\n' "${WINDOWS_MCP_VERSION}" >"${CANON_DIR}/telemetry/windows-mcp.version"
        else
            log "WARNING: wslbridge probe failed; run install.ps1 on the Windows host first"
        fi
    else
        log "WARNING: powershell.exe not on PATH; wslbridge disabled"
    fi
fi

# ---------- 3. Cursor activation symlink ----------
mkdir -p "$(dirname "$CURSOR_SKILL_DIR")"
if [[ -L "$CURSOR_SKILL_DIR" ]]; then
    current="$(readlink "$CURSOR_SKILL_DIR")"
    if [[ "$current" != "$CANON_DIR" ]]; then
        log "relinking $CURSOR_SKILL_DIR -> $CANON_DIR (was $current)"
        rm -f "$CURSOR_SKILL_DIR"
        ln -s "$CANON_DIR" "$CURSOR_SKILL_DIR"
    else
        log "cursor symlink already correct"
    fi
elif [[ -e "$CURSOR_SKILL_DIR" ]]; then
    log "WARNING: $CURSOR_SKILL_DIR exists and is not a symlink; leaving untouched"
else
    log "creating cursor symlink $CURSOR_SKILL_DIR -> $CANON_DIR"
    ln -s "$CANON_DIR" "$CURSOR_SKILL_DIR"
fi

# ---------- 4. Runtime directory (best-effort mirror) ----------
mkdir -p "$(dirname "$RUNTIME_DIR")"
if [[ -L "$RUNTIME_DIR" ]]; then
    current="$(readlink "$RUNTIME_DIR")"
    if [[ "$current" != "$CANON_DIR" ]]; then
        log "relinking $RUNTIME_DIR -> $CANON_DIR"
        rm -f "$RUNTIME_DIR"
        ln -s "$CANON_DIR" "$RUNTIME_DIR"
    else
        log "runtime symlink already correct"
    fi
elif [[ -d "$RUNTIME_DIR" ]]; then
    log "runtime dir exists as real directory; install.ps1 manages it on Windows nodes"
else
    ln -s "$CANON_DIR" "$RUNTIME_DIR"
fi

# ---------- 5. Mem0 + MiniMax op smoke (fingerprint only) ----------
if command -v op >/dev/null 2>&1; then
    if op whoami >/dev/null 2>&1; then
        log "op whoami OK"
        cred_len=0
        if cred="$(op read 'op://Cursor_IronClaw/MiniMax M2.7 highspeed API 1/credential' 2>/dev/null)"; then
            cred_len=${#cred}
            sha_prefix="$(printf '%s' "$cred" | sha256sum | awk '{print substr($1,1,12)}')"
            log "minimax credential: length=${cred_len} sha256_prefix=${sha_prefix}"
            mkdir -p "${CANON_DIR}/telemetry"
            printf 'length=%s sha256_prefix=%s\n' "$cred_len" "$sha_prefix" \
                >"${CANON_DIR}/telemetry/minimax-credential.fingerprint"
            unset cred
        else
            log "minimax credential read skipped (item missing or op not signed in)"
        fi
    else
        log "op whoami not signed in; set OP_SERVICE_ACCOUNT_TOKEN to enable"
    fi
fi

# ---------- 6. systemd --user preflight (WSL1 only, if systemd-user is up) ----------
if $IS_WSL && [[ "$(loginctl show-user "$USER" 2>/dev/null | grep -c 'Linger=yes')" -ge 0 ]]; then
    user_unit_dir="${HOME}/.config/systemd/user"
    mkdir -p "$user_unit_dir"
    preflight_sh="${CANON_DIR}/scripts/preflight.sh"
    if [[ -x "$preflight_sh" ]]; then
        cat >"${user_unit_dir}/ironclaw-preflight.service" <<EOF
[Unit]
Description=IronClaw devops-sysadmin preflight
After=network.target

[Service]
Type=oneshot
ExecStart=${preflight_sh}
EOF
        cat >"${user_unit_dir}/ironclaw-preflight.timer" <<'EOF'
[Unit]
Description=Run IronClaw preflight every 3 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
Unit=ironclaw-preflight.service

[Install]
WantedBy=timers.target
EOF
        if command -v systemctl >/dev/null 2>&1 && systemctl --user is-system-running --quiet 2>/dev/null; then
            systemctl --user daemon-reload
            systemctl --user enable --now ironclaw-preflight.timer || true
            log "enabled ironclaw-preflight.timer (user)"
        else
            log "systemd --user not running; unit installed but not activated"
        fi
    fi
fi

log "install.sh done"
