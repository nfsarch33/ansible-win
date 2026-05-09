SHELL := /usr/bin/env bash

.PHONY: test
test:
	python3 -m unittest discover -s ansible/tests -p 'test_*.py'

.PHONY: tree
tree:
	@python3 -c "from pathlib import Path; [print(path) for path in sorted(Path('.').glob('**/*')) if '.git' not in path.parts]"
