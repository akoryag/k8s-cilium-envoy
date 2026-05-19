# AGENTS.md

## Project

Ansible playbook to provision a Kubernetes v1.35 cluster on Ubuntu noble with Cilium CNI and Envoy ingress, fronted by HAProxy (port 80/443 → 8080).

Two sub-projects in this repo:
- **Ansible** (`playbook.yml`, `roles/`) — system prep (kernel modules, sysctl, Docker/containerd, k8s packages) on all hosts.
- **Packer** (`packer/`) — builds a custom Ubuntu 24.04 QCOW2 image with qemu-guest-agent via HashiCorp Packer + cloud-init.

## Key commands

```bash
# Ansible: syntax check, dry run, apply
ansible-playbook -i inventory.ini playbook.yml --syntax-check
ansible-playbook -i inventory.ini playbook.yml --check --diff
ansible-playbook -i inventory.ini playbook.yml

# Packer: build QCOW2 image (run from packer/ directory)
packer init ubuntu-qcow.pkr.hcl
packer validate ubuntu-qcow.pkr.hcl
packer build ubuntu-qcow.pkr.hcl
```

## Ansible playbook scope

The playbook **only** runs the `common` role on all hosts (`any_errors_fatal: true`). It does **not** run `kubeadm init`, `kubeadm join`, or install Cilium/Envoy/HAProxy. Those are manual steps (see README.md).

Group vars (`group_vars/all.yml`): `k8s_version`, `k8s_minor`, `pod_cidr`.

## Notable details

- `roles/common/tasks/k8s.yml` uses `mirror.yandex.ru/mirrors/pkgs.k8s.io` (Russian mirror) — not the official pkgs.k8s.io repo.
- Docker repo in `roles/common/tasks/docker.yml` hardcodes `noble` — not parameterized.
- K8s packages (`kubelet`, `kubeadm`, `kubectl`) are held via `dpkg_selections` to prevent accidental upgrades.
- `ansible.cfg` disables host key checking and retry files.
- `ansible_user` is **not** set in inventory — defaults to the control-node user; SSH key auth expected.
- Inventory defines only `master-1`; worker nodes are commented out.

## Post-Ansible manual steps (summarized from README.md)

1. `kubeadm init --pod-network-cidr=10.244.0.0/16` on master
2. `kubeadm join ...` on workers
3. Label ingress node: `kubectl label node <name> node-role.kubernetes.io/ingress=`
4. Install Cilium with Envoy (see README.md for exact `cilium install` flags)
5. Delete kube-proxy: `kubectl -n kube-system delete ds kube-proxy`
6. Apply HAProxy redirect: `kubectl apply -f lb-redirect.yaml`

## Packer details

- Source image: Ubuntu 24.04 cloud image (`ubuntu-24.04-server-cloudimg-amd64.img`).
- Output: `ubuntu-24.04-custom.qcow2` (QEMU/KVM, qcow2 format, compressed).
- SSH into the builder VM as `ubuntu` / password `packer`.
- Cloud-init `user-data` must be minimal — only setup user/SSH. Do **not** use `package_update`, `packages`, or `power_state` in cloud-init; Packer provisioners handle package install and `shutdown_command` handles poweroff. `power_state` in cloud-init will shut down the VM before Packer can SSH in.
- The top-level `password` key in cloud-init is **deprecated on Ubuntu 24.04** (cloud-init 24.x) and causes `status: error`. Use `users[0].passwd` (SHA-512 hash from `openssl passwd -6`) instead.
- `cd_files = ["./cloud-init/user-data", "./cloud-init/meta-data"]` with `cd_label = "cidata"` — both files must be at the root of the ISO for NoCloud datasource.
- Checksum must be updated in `packer/ubuntu-qcow.pkr.hcl` if the upstream image changes.

## Gotchas

- `ansible_user` is undefined — the playbook connects as whatever user runs it on the control node. Add `ansible_user` to inventory if that is not desired.
- Packer cloud-init user-data contains a plaintext password hash for `packer`. The hash was generated with `openssl passwd -6`.
