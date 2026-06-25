# k8s-cilium-envoy

Ansible-плейбук для развёртывания Kubernetes-кластера с Cilium (kube-proxy replacement) и Envoy ingress controller. Поддерживается HA control plane, зеркала репозиториев и образов для работы в ограниченной сети, предварительная загрузка образов.

## Что делает плейбук

1. **Подготовка всех нод** (`roles/common`) — отключение swap, модули ядра, sysctl, зеркала APT, Docker, containerd, Kubernetes, pre-pull образов.
2. **Инициализация control plane** (`roles/init`) — `kubeadm init` на первом мастере с `--control-plane-endpoint`.
3. **Присоединение нод** (`roles/join`) — дополнительные мастера (с `--control-plane`) и воркеры через `kubeadm join`.
4. **Постконфигурация** (`roles/post-cluster`) — установка Cilium через Helm, удаление `kube-proxy`.

## Требования

- Ansible 2.14+
- Python 3 на управляющей машине
- SSH-доступ к нодам (root или `become`)

Установка коллекций:

```bash
ansible-galaxy collection install -r requirements.yml
```

## Быстрый старт

### 1. Инвентарь

Отредактируйте `inventory.ini`:

```ini
[master]
master-1 ansible_host=10.10.10.30
master-2 ansible_host=10.10.10.31
master-3 ansible_host=10.10.10.32

[workers]
worker-1 ansible_host=10.10.10.40
```

### 2. Переменные

Основные настройки в `group_vars/all.yml`:

| Переменная | По умолчанию | Описание |
|---|---|---|
| `k8s_version` | `1.35.4` | Версия Kubernetes |
| `pod_cidr` | `10.244.0.0/16` | Pod network CIDR |
| `control_plane_vip` | `10.10.10.30` | VIP или IP первого мастера для `--control-plane-endpoint` |
| `cilium_version` | `1.19.3` | Версия Helm-чарта Cilium |
| `repo_mirror` | `mirror.yandex.ru` | Зеркало APT и pkgs.k8s.io |
| `k8s_image_repo` | `registry.aliyuncs.com/google_containers` | Репозиторий образов kubeadm |
| `quay_image_repo` | `dockerhub.timeweb.cloud` | Зеркало образов Cilium |

### 3. Запуск

```bash
ansible-playbook -i inventory.ini playbook.yml
```

Плейбук выполняется в четыре этапа:

| Этап | Хосты | Действие |
|---|---|---|
| Configure all hosts | `all` | Подготовка ОС, Docker, K8s, pre-pull образов |
| Initialize control-plane | `master` (serial: 1) | `kubeadm init` + join остальных мастеров |
| Join worker nodes | `workers` (serial: 1) | `kubeadm join` воркеров |
| Post-cluster configuration | `master[0]` | Cilium + удаление kube-proxy |

## Архитектура кластера

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  master-1   │  │  master-2   │  │  master-3   │
│ (init)      │  │ (join CP)   │  │ (join CP)   │
└──────┬──────┘  └──────┬──────┘  └──────┬──────┘
       │                │                │
       └────────────────┼────────────────┘
                        │ control-plane-endpoint (VIP)
              ┌─────────┴─────────┐
              │     workers       │
              └───────────────────┘
                        │
              ┌─────────┴─────────┐
              │ Cilium + Envoy    │
              │ (kube-proxy off)  │
              └───────────────────┘
```

Cilium устанавливается с параметрами:

- `kubeProxyReplacement: true` — полная замена kube-proxy
- `ingressController.enabled: true`, `loadbalancerMode: dedicated`
- `envoy.enabled: true`

После установки Cilium DaemonSet `kube-proxy` удаляется из `kube-system`.

## Структура проекта

```
.
├── playbook.yml              # Главный плейбук
├── inventory.ini             # Инвентарь нод
├── group_vars/all.yml        # Переменные кластера
├── requirements.yml          # Ansible-коллекции
├── roles/
│   ├── common/               # Подготовка ОС, Docker, K8s, pre-pull
│   ├── init/                 # kubeadm init на первом мастере
│   ├── join/                 # Присоединение мастеров и воркеров
│   └── post-cluster/         # Cilium через Helm, удаление kube-proxy
├── packer/                   # Сборка QCOW2-образа с предустановкой
│   ├── ubuntu-qcow.pkr.hcl
│   └── cloud-init/
└── lb-redirect.yaml          # HAProxy для редиректа 80/443 → Envoy (ручное применение)
```

## Сборка образа (Packer)

В каталоге `packer/` есть конфигурация для создания QCOW2-образа Ubuntu 24.04 с предустановленным плейбуком:

```bash
cd packer
packer init ubuntu-qcow.pkr.hcl
packer build ubuntu-qcow.pkr.hcl
```

Образ собирается через QEMU/KVM, cloud-init задаёт пользователя `ubuntu`, затем выполняется `ansible-local` с `playbook.yml`.

## Дополнительные ресурсы

### lb-redirect.yaml

Манифест HAProxy в `hostNetwork` для перенаправления трафика с портов 80/443 на Envoy (`127.0.0.1:8080`). Требует метку ноды `role=ingress`. Применяется вручную:

```bash
kubectl apply -f lb-redirect.yaml
```

### Зеркала образов

Для ускорения развёртывания в закрытых сетях плейбук:

- переключает APT на `mirror.yandex.ru`
- использует зеркала Docker registry (`mirror.gcr.io`, `dockerhub.timeweb.cloud`)
- pre-pull образов Kubernetes (на мастерах) и Cilium (на всех нодах) до `kubeadm init`

Список образов Cilium задаётся в `cilium_images` в `group_vars/all.yml`.

## Полезные команды

```bash
# Создать новый join-токен
kubeadm token create --print-join-command

# Загрузить сертификаты для join control-plane
kubeadm init phase upload-certs --upload-certs

# Статус Cilium
kubectl -n kube-system rollout status daemonset cilium
```

## Ссылки

- [Kubespray: mirror operations](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/operations/mirror.md)
- [Cilium Helm installation](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
