#!/usr/bin/env bash
# devops-sysadmin: rsync the canonical skill dir to the NAS bundle path.
# Safe to re-run; idempotent. Intended to be called from CI on every merge to
# main and manually by the operator via `make skill-sync`.
#
# SMB on Synology does not preserve symlinks, so we deliberately use -L to
# dereference (the canonical dir only contains regular files anyway).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DEFAULT='/Volumes/filesys3/scripts/devops-sysadmin'   # macOS Finder-mounted SMB
DEST="${1:-$DEST_DEFAULT}"

if [[ ! -d "$SRC" ]]; then
    echo "canonical skill dir missing: $SRC" >&2
    exit 1
fi

if [[ ! -d "$DEST" ]]; then
    echo "NAS destination not mounted: $DEST" >&2
    echo "mount it in Finder (Network -> SynologyRouter -> filesys3) or pass a path" >&2
    exit 1
fi

echo "rsync $SRC -> $DEST"
rsync -avL --delete \
    --exclude '.git' \
    --exclude '.DS_Store' \
    --exclude 'telemetry/*.sha' \
    --exclude 'telemetry/*.fingerprint' \
    "$SRC"/ "$DEST"/

echo "done"
