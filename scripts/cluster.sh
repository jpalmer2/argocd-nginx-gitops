#!/bin/bash

# add nodes to host file
sudo echo "172.20.1.50 master" >> /etc/hosts
sudo echo "172.20.1.51 worker1" >> /etc/hosts
sudo echo "172.20.1.52 worker2" >> /etc/hosts

# enable kernel modules
cat << EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# add system level settings for k8s network 
cat << EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1 
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

# enable guest additions
sudo apt install build-essential dkms

# install and setup containerd
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

# disable swap 
sudo swapoff -a 
sudo sed -i '/swap/d' /etc/fstab

# install k8s packages
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# VirtualBox NAT (10.0.2.15) is the default route on every VM; pin kubelet to the
# host-only NIC so node InternalIPs are unique.
NODE_IP="$(hostname -I | tr ' ' '\n' | grep '^172.20.1.' | head -1)"
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" | sudo tee /etc/default/kubelet

sudo systemctl enable --now kubelet