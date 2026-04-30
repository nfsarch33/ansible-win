SHELL := /usr/bin/env bash

.PHONY: check test
check:
	@pwsh -NoProfile -File ./agent-bootstrap/devops-sysadmin/scripts/check-windows-mcp-version.ps1 -ExpectedVersion 0.7.1 -NoInstall || true

test:
	python3 -m unittest discover -s ansible/tests -p 'test_*.py'

.PHONY: tree
tree:
	@python3 -c "from pathlib import Path; [print(path) for path in sorted(Path('.').glob('**/*')) if '.git' not in path.parts]"
