# 🧩 Bare-Metal Kubernetes with Cilium (Native Routing)

This project automates the deployment of a **lightweight, fully functional Kubernetes cluster** on **bare metal or Proxmox VMs**, using **Cilium** as the CNI plugin with **native routing mode** (no overlays).

The setup is designed for infrastructure engineers who want to understand and operate Kubernetes at a low level — without relying on managed services like EKS, AKS, or GKE.

---

## 🚀 Features

- **Kubernetes v1.34.0** (via kubeadm)
- **Cilium v1.16.2** with:
  - `kubeProxyReplacement=true`
  - `routingMode=native`
  - `ipam.mode=kubernetes`
- Optional **Hubble** observability and UI
- **Swap disabled** and **sysctl tuned** for Kubernetes
- **Static routing between nodes**
- Tested on **Debian 13 (Trixie)** — compatible with **Debian 12 (Bookworm) or newer**

---

## 🧱 Prerequisites

| Component | Description |
|------------|--------------|
| OS | Debian 13 (Trixie) or Debian 12 (Bookworm) |
| Virtualization | Proxmox VE or bare metal |
| Network | Nodes must be reachable via Layer 3 (static routes added for pod CIDRs) |
| Access | Passwordless `sudo` or SSH key access between nodes |
| DNS | Optional; `/etc/hosts` can be used for internal resolution |

---

## 🖥️ Node Layout

| Role | Hostname | IP Address | Pod CIDR |
|------|-----------|-------------|-----------|
| Control Plane | `k8s-t-master.home.azurewrath.nl` | `192.168.1.24` | `10.244.0.0/24` |
| Worker | `k8s-t-worker.home.azurewrath.nl` | `192.168.1.25` | `10.244.1.0/24` |

---


