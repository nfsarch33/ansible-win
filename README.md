# ansible-win

Private Windows 11 workstation bootstrap and fleet onboarding automation for the IronClaw/Cylrl home fleet.

## Scope

- Windows admin PowerShell bootstrap scripts.
- OpenSSH, firewall, Chocolatey, UV, and Windows-MCP setup.
- DevOps/SysAdmin IronClaw node onboarding bundle.
- Ansible collections and future playbooks for day-2 drift management.

## Layout

- `agent-bootstrap/devops-sysadmin/` — copied from `ai-agent-business-stack/skills/devops-sysadmin/`; compatibility copy remains in the source repo until consumers switch.
- `ansible/` — Ansible collection scaffold copied from `ai-agent-business-stack/infra/ansible/`.
- `docs/repo-boundaries.md` — ownership rules for this repo versus business stack and ops repos.
- root `*.ps1` — legacy workstation bootstrap scripts retained from the original repo.

## Quick Start

Run PowerShell as Administrator on a Windows 11 target:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install-all.ps1
```

For DevOps/SysAdmin IronClaw node onboarding:

```powershell
.\agent-bootstrap\devops-sysadmin\install.ps1 -Pull -Mode Node
.\agent-bootstrap\devops-sysadmin\scripts\preflight.ps1
```

## Boundary

This repo is personal/private. Do not store real secrets here. 1Password service-account references and redacted examples are allowed; resolved tokens are not.

---

## Legacy README

# A set of powershell scripts to automate Windows admin tasks

Run powershell as administrator then enter the following: 

`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

Go to the repo root, then run `install-all.ps1` to start the script.
