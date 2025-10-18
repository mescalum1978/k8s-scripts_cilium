#!/bin/bash

# Assumptions:
# - machine with single disk
# - /etc/network/interfaces and /etc/hosts are configured before running this script including routing
# - For master node installation with Cilium as CNI
# - Tested on Debian 13

K8S_VERSION="1.34.0"
CILIUM_VERSION="1.16.2"
MASTER_IP=$(hostname -I | awk '{print $1}')

echo "[1/7] Updating system, disabling swap..."
sudo apt update && sudo apt upgrade -y

# Turn off all active swap immediately
sudo swapoff -a

# Comment out any swap entries in /etc/fstab so swap doesn't mount on reboot
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Prevent systemd from activating any swap in the future
sudo systemctl mask swap.target
sudo systemctl mask dev-sda3.swap 2>/dev/null || true   # optional: mask specific swap device if exists

# Verify
echo "Active swap after disabling:"
swapon --show || echo "swapon command not found, swap likely disabled"
echo "swap.target status:"
systemctl status swap.target | head -n 10

# sudo swapoff -a
# sudo sed -i '/ swap / s/^/#/' /etc/fstab
# sudo systemctl mask swap.target

echo "[2/7] Installing prerequisite packages..."
sudo apt install -y apt-transport-https ca-certificates curl gpg htop

echo "[3/7] Installing and configuring containerd..."
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo sed -i 's|bin_dir = "/usr/lib/cni"|bin_dir = "/opt/cni/bin"|' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "[4/7] Adding Kubernetes $K8S_VERSION repo and installing packages..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes.gpg
echo "deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "[5/7] Applying sysctl settings..."
sudo modprobe br_netfilter
echo "br_netfilter" | sudo tee /etc/modules-load.d/k8s.conf
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sudo sysctl --system

echo "[6/7] Disabling nftables (if active)..."
sudo systemctl stop nftables || true
sudo systemctl disable nftables || true

echo "[7/7] Installing CNI plugins..."
CNI_VERSION="v1.5.1"
ARCH="amd64"
sudo mkdir -p /opt/cni/bin

curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz

echo "[Master] Initializing Kubernetes cluster..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

echo "[Master] Configuring kubectl for current user..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Remove kube-proxy and install Helm
kubectl -n kube-system delete ds kube-proxy
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash


echo "[Master] Installing Cilium $CILIUM_VERSION..."
# Install Cilium CLI
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
sudo tar xzvf cilium-linux-amd64.tar.gz -C /usr/local/bin
rm cilium-linux-amd64.tar.gz

# Fix ownership just before Cilium install
sudo chown -R root:root /opt/cni/bin
sudo chmod 755 /opt/cni/bin

# Join worker node(s) before proceeding!

# Install Cilium with direct routing (recommended for bare metal)
cilium install \
  --version ${CILIUM_VERSION} \
  --set kubeProxyReplacement=true \
  --set routingMode=native \
  --set ipv4NativeRoutingCIDR=10.244.0.0/16 \
  --set k8sServiceHost=${MASTER_IP} \
  --set k8sServicePort=6443 \
  --set ipam.mode=kubernetes \
  --set cni.binPath=/opt/cni/bin \
  --set cni.confPath=/etc/cni/net.d

echo "Verifying Cilium status..."
cilium status --wait

echo "Enabling Hubble..."
cilium hubble enable --relay --ui # deploys Hubble Relay to aggregate metrics

echo "Deploying Hubble UI..."
cilium hubble ui install

echo "Waiting for Cilium and Hubble pods to be ready..."
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=cilium --timeout=180s
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=hubble-relay --timeout=180s
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=hubble-ui --timeout=180s

echo "[6/6] Verifying Hubble status..."
cilium hubble status

echo "Kubernetes $K8S_VERSION cluster ready with Cilium $CILIUM_VERSION network!"
