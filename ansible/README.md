# Ansible Dependencies

Install required collections instead of committing vendored dependency trees:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

Future Windows 11 workstation playbooks should live under `ansible/playbooks/` and roles under `ansible/roles/`.
