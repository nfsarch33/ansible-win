# ansible-win

Generic Windows 11 workstation bootstrap and onboarding automation.

## Scope

- Windows admin PowerShell bootstrap scripts.
- OpenSSH, firewall, Chocolatey, UV, and Windows-MCP setup.
- Ansible collections and future playbooks for day-2 drift management.

## Layout

- `ansible/` — Ansible collection scaffold for Windows day-2 drift management.
- `docs/repo-boundaries.md` — ownership rules for this repo.
- root `*.ps1` — legacy workstation bootstrap scripts retained from the original repo.

## Quick Start

Run PowerShell as Administrator on a Windows 11 target:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install-all.ps1
```

## Boundary

Operator-specific DevOps/SysAdmin onboarding (the previous
`agent-bootstrap/devops-sysadmin/` bundle) was relocated to a
separate private operator repo in v323-5. This repo retains only
the generic Windows bootstrap scripts and the Ansible scaffold.

Do not commit real secrets, fleet hostnames, vault names, or
operator-specific paths to this repository. Use generic
placeholders (`<your-host>`, `<vault-name>`, `<your-path>`) in
documentation and scripts.

---

## Legacy README

# A set of powershell scripts to automate Windows admin tasks

Run powershell as administrator then enter the following: 

`Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

Go to the repo root, then run `install-all.ps1` to start the script.
