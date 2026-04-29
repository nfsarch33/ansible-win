# Repo Boundaries

`ansible-win` is the private source of truth for Windows 11 workstation bootstrap, OpenSSH/firewall setup, Chocolatey/UV prerequisites, Windows-MCP drift checks, and DevOps/SysAdmin node onboarding assets.

`ai-agent-business-stack` keeps product/business logic and may keep a compatibility copy of the `devops-sysadmin` skill until consumers are switched to this repo. New Windows host automation should land here first.

`ironclaw-ops` remains the fleet deployment and Mission Control runtime repo. It should consume this repo as an external dependency rather than embedding Windows workstation scripts.
