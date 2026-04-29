SHELL := /usr/bin/env bash

.PHONY: check
check:
	@pwsh -NoProfile -File ./agent-bootstrap/devops-sysadmin/scripts/check-windows-mcp-version.ps1 -ExpectedVersion 0.7.1 -NoInstall || true

.PHONY: tree
tree:
	@python3 - <<'PY'
from pathlib import Path
for path in sorted(Path('.').glob('**/*')):
    if '.git' in path.parts:
        continue
    print(path)
PY
