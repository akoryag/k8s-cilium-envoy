# AGENTS.md

## Project
Ansible playbook to provision a Kubernetes v1.35 cluster on Ubuntu noble with Cilium CNI and Envoy ingress, fronted by HAProxy for port 80/443 → 8080 redirect.

## Key commands

```bash
# Run the playbook (requires passwordless sudo on targets)
ansible-playbook -i inventory.ini playbook.yml

# Syntax check
ansible-playbook -i inventory.ini playbook.yml --syntax-check

# Dry run
ansible-playbook -i inventory.ini playbook.yml --check --diff

# After Ansible completes, follow README.md for kubeadm init/join and Cilium install
```

## What the playbook does NOT automate
The Ansible role only handles system prep (kernel modules, sysctl, Docker/containerd, k8s packages). It does **not** run `kubeadm init`, `kubeadm join`, or install Cilium. Those steps are manual — see README.md.

## Gotchas

- **`roles/common/habdlers/` is misspelled.** Ansible auto-discovers handlers from `handlers/`, not `habdlers/`. The handlers in that directory (`restart docker`, `restart journald`) are **silently ignored** unless the directory is renamed or tasks include them explicitly.

- No `.gitignore` — standard Ansible artifacts (`.retry` files, `*.pyc`) will show up in git status.

- `group_vars/all.yml` defines `pause_version: "3.9"` which is unused by current tasks.

- `ansible_user` is not defined in inventory — defaults to the current user on the control node with SSH key auth assumed.
