# k8s-cilium-envoy
1. Подготовка системы (НА ВСЕХ НОДАХ)


# Включаем нужные модули ядра

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter



# sysctl настройки

cat <<EOF | tee /etc/sysctl.d/99-kubernetes.conf
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

sysctl --system


2. Установка Docker

# Добавим gpg ключ
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu noble stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Обновляемся
apt -y update

# Устанавливаем docker
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Заставляем докер работать чуть иначе и ограничиваем размер логов до 100 мб:
cat <<EOF > /etc/docker/daemon.json
{
   "exec-opts": ["native.cgroupdriver=systemd"],
   "log-driver":"json-file",
   "log-opts":{
      "max-size":"100m",
      "max-file":"1"
   }
}
EOF

# Настроим максимальный размер логов:
echo 'SystemMaxUse=200M' >> /etc/systemd/journald.conf


# Конфиг containerd
containerd config default > /etc/containerd/config.toml

# Включаем systemd cgroup:
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# Устанавливаем Kubernetes:
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/kubernetes-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
apt -y update
apt install -y kubelet kubeadm kubectl


4. Инициализация MASTER-ноды

kubeadm init \
  --pod-network-cidr=10.244.0.0/16


# Настройка kubectl
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

5. Подключение WORKER-нод

# После kubeadm init тебе покажут команду вида:

kubeadm join <IP>:6443 --token ... --discovery-token-ca-cert-hash ...

6. Установка Cilium + Envoy

# Установка CLI

curl -L --remote-name https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
mv cilium /usr/local/bin/

# Посмотрите список нод
kubectl get nodes

# Добавьте метку (замените <node-name> на имя вашей ноды)
kubectl label node <node-name> node-role.kubernetes.io/ingress=""

# Установка Cilium
cilium install \
  --set kubeProxyReplacement=true \
  --set ingressController.enabled=true \
  --set ingressController.loadbalancerMode=shared \
  --set ingressController.hostNetwork.enabled=true \
  --set ingressController.hostNetwork.nodes.matchLabels.role=ingress \
  --set envoy.enabled=true \
  --set envoy.nodeSelector.role=ingress

  7. Удаляем kube-proxy (ВАЖНО)
  kubectl -n kube-system delete ds kube-proxy

