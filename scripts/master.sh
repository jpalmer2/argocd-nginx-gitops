#!/bin/bash

# kubeadm to initilize the cluster
sudo kubeadm init --apiserver-advertise-address=172.20.1.50 --pod-network-cidr 192.168.0.0/16

# set kubeconfig
sudo mkdir -p /home/vagrant/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
sudo chown vagrant:vagrant /home/vagrant/.kube/config
export KUBECONFIG=/home/vagrant/.kube/config

# setup networking using calico
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/tigera-operator.yaml
kubectl create -f /home/vagrant/custom-resources-bpf.yaml

# create join token
sudo kubeadm token create --print-join-command > /home/vagrant/data/join_token.txt