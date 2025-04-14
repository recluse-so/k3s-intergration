#! /bin/bash

# install multipass via brew
brew install multipass
multipass --version

# create a new k3s cluster
multipass launch --name k3sCluster --cpus 2 --memory 2G --disk 10G

# list the multipass instances
multipass list

# login to the ubuntu instance
multipass shell k3sCluster

# install k3s on the cluster
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.30.8+k3s1" sh - 

# GET NODES 
kubectl get nodes

# get the token and copy paste it into the k3s/config.yaml file
cat /var/lib/rancher/k3s/server/token

# create a k3s agent
multipass launch --name k3sAgent --cpus 2 --memory 2G --disk 10G

# get the ip address of the k3s cluster
multipass list

echo SERVER_IP=192.168.64.2
# login to the k3s agent
multipass shell k3sAgent

# install k3s on the agent
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.30.8+k3s1" INSTALL_K3S_EXEC="agent--server $SERVER_IP --token $TOKEN" sh - 

# install k3s with calico cni
multipass exec k3sCluster -- sudo k3s cni install calico


