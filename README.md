# k8s-cilium-envoy

Ansible-плейбук для развёртывания Kubernetes-кластера с Cilium (kube-proxy replacement), Envoy ingress controller, Longhorn, cert-manager и CloudNativePG. Поддерживается HA control plane, зеркала репозиториев и образов для работы в ограниченной сети, предварительная загрузка образов.

## Что делает плейбук

1. **Подготовка всех нод** (`roles/common`) — отключение swap, модули ядра, sysctl, зеркала APT, Docker, containerd, Kubernetes, Helm (на мастерах), подготовка ОС для Longhorn, pre-pull образов.
2. **Инициализация control plane** (`roles/init`) — `kubeadm init` на первом мастере с `--control-plane-endpoint`.
3. **Присоединение нод** (`roles/join`) — дополнительные мастера (с `--control-plane`) и воркеры через `kubeadm join`.
4. **Постконфигурация** (`roles/post-cluster`) — установка через Helm на `master[0]`: Cilium, Longhorn, cert-manager, CloudNativePG.

## Требования

- Ansible 2.14+
- Python 3 на управляющей машине
- SSH-доступ к нодам (root или `become`)
- Исходящий доступ с `master[0]` к Helm-репозиториям (Cilium, Longhorn, cert-manager, CloudNativePG)

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
| `helm_version` | `3.17.2` | Версия Helm (устанавливается на мастерах) |
| `pod_cidr` | `10.244.0.0/16` | Pod network CIDR |
| `control_plane_vip` | `10.10.10.30` | VIP или IP первого мастера для `--control-plane-endpoint` |
| `manifests_dir` | `/opt/manifests` | Каталог манифестов на нодах |
| `repo_mirror` | `mirror.yandex.ru` | Зеркало APT и pkgs.k8s.io |
| `k8s_image_repo` | `registry.aliyuncs.com/google_containers` | Репозиторий образов kubeadm |
| `docker_image_repo` | `dockerhub.timeweb.cloud` | Зеркало образов Cilium и Longhorn |
| `quay_image_repo` | `quay.m.daocloud.io` | Зеркало образов cert-manager |
| `cilium_version` | `1.19.3` | Версия Helm-чарта Cilium |
| `longhorn_version` | `1.12.0` | Версия Helm-чарта Longhorn |
| `cert_manager_version` | `v1.17.2` | Версия Helm-чарта cert-manager |
| `cloudnativepg_version` | `0.28.3` | Версия Helm-чарта CloudNativePG |

Helm values для компонентов — в `roles/post-cluster/defaults/main.yml`, списки образов для pre-pull — в `roles/common/defaults/main.yml`.

### 3. Запуск

```bash
ansible-playbook -i inventory.ini playbook.yml
```

Плейбук выполняется в четыре этапа:

| Этап | Хосты | Действие |
|---|---|---|
| Configure all hosts | `all` | Подготовка ОС, Docker, K8s, Helm, Longhorn OS, pre-pull образов |
| Initialize control-plane | `master` (serial: 1) | `kubeadm init` + join остальных мастеров |
| Join worker nodes | `workers` (serial: 1) | `kubeadm join` воркеров |
| Post-cluster configuration | `master[0]` | Cilium, Longhorn, cert-manager, CloudNativePG |

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
              │ Longhorn          │
              │ cert-manager      │
              │ CloudNativePG     │
              └───────────────────┘
```

### Cilium

Устанавливается с параметрами:

- `kubeProxyReplacement: true` — полная замена kube-proxy
- `ingressController.enabled: true`, `loadbalancerMode: dedicated`
- `envoy.enabled: true`
- образы из `docker_image_repo`

После установки Cilium DaemonSet `kube-proxy` удаляется из `kube-system`. При включённом `cilium_l2_announcements_enabled` применяются L2 announcement policy и LoadBalancer IP pool (манифесты в `{{ manifests_dir }}/cilium/`).

### Longhorn

- Подготовка ОС на всех нодах: `open-iscsi`, `nfs-common`, модуль `iscsi_tcp`, сервисы `iscsid`, `open-iscsi`, `rpcbind`
- Установка оператора через Helm в namespace `longhorn-system`
- Образы через `global.imageRegistry: docker_image_repo`

### cert-manager

- Namespace `cert-manager`, CRDs включены
- Образы из `cert_manager_image_repo` (по умолчанию `quay_image_repo`)

### CloudNativePG

- Оператор в namespace `cnpg-system`
- Release name `cnpg`, chart `cnpg/cloudnative-pg`

## Структура проекта

```
.
├── playbook.yml              # Главный плейбук
├── inventory.ini             # Инвентарь нод
├── group_vars/all.yml        # Переменные кластера
├── requirements.yml          # Ansible-коллекции
├── ansible.cfg
├── manifests/
│   └── ingress-test.yaml     # Тестовый Ingress для Cilium
└── roles/
    ├── common/               # Подготовка ОС, Docker, K8s, Helm, Longhorn OS, pre-pull
    ├── init/                 # kubeadm init на первом мастере
    ├── join/                 # Присоединение мастеров и воркеров
    └── post-cluster/         # Helm: Cilium, Longhorn, cert-manager, CloudNativePG
```

## Зеркала и pre-pull

Для ускорения развёртывания в закрытых сетях плейбук:

- переключает APT на `mirror.yandex.ru`
- использует зеркала Docker registry (`mirror.gcr.io`, `dockerhub.timeweb.cloud`)
- pre-pull образов Kubernetes (на мастерах) и Cilium (на всех нодах) до `kubeadm init`
- устанавливает Helm и плагин `helm-diff` на control-plane нодах

Список образов Cilium задаётся в `cilium_images` (`roles/common/defaults/main.yml`).

Helm-задачи post-cluster выполняются на `master[0]` через `kubectl` и `helm` с kubeconfig `/etc/kubernetes/admin.conf`. На машине, с которой запускается Ansible, `kubectl`/`helm` не требуются.

## Полезные команды

```bash
# Создать новый join-токен
kubeadm token create --print-join-command

# Загрузить сертификаты для join control-plane
kubeadm init phase upload-certs --upload-certs

# Статус Cilium
kubectl -n kube-system rollout status daemonset cilium

# Статус Longhorn
kubectl -n longhorn-system rollout status daemonset longhorn-manager

# Статус cert-manager
kubectl -n cert-manager rollout status deployment cert-manager

# Статус CloudNativePG
kubectl -n cnpg-system rollout status deployment cnpg-cloudnative-pg
```

## Ссылки

- [Kubespray: mirror operations](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/operations/mirror.md)
- [Cilium Helm installation](https://docs.cilium.io/en/stable/installation/k8s-install-helm/)
- [Longhorn installation](https://longhorn.io/docs/latest/deploy/install/)
- [cert-manager Helm installation](https://cert-manager.io/docs/installation/helm/)
- [CloudNativePG operator chart](https://github.com/cloudnative-pg/charts)
