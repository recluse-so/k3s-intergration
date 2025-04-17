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

# generate a random token
export TOKEN_SERVER=$(openssl rand -base64 32)

# install k3s on the cluster
curl -sfL https://get.k3s.io | sh -s - server \
    --token $TOKEN_SERVER \
    --cluster-init

# GET NODES 
sudo kubectl get nodes

# get the token and copy paste it into the k3s/config.yaml file
sudo cat /var/lib/rancher/k3s/server/token

exit 

export TOKEN_AGENT=K10d29b3865afb8743cbe646492eda4cbba5c5261d1f6f21f6f855b0ccbe32f5778::server:sNmxP4YPF+LjLh8ZDOx3pebzgmcj4GcmPfVI1eA3m2k=

# create a k3s agent
multipass launch --name k3sAgent --cpus 2 --memory 2G --disk 10G

# get the ip address of the k3s cluster
multipass list

# set the server ip address
export SERVER_IP=https://192.168.64.2:6443

# login to the k3s agent
multipass shell k3sAgent

# install k3s on the agent
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://192.168.64.2:6443 --token K10d29b3865afb8743cbe646492eda4cbba5c5261d1f6f21f6f855b0ccbe32f5778::server:sNmxP4YPF+LjLh8ZDOx3pebzgmcj4GcmPfVI1eA3m2k=" sh -
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" K3S_TOKEN="mypassword" sh -s - --server https://k3s.example.com

# install k3s 
kubectl get nodes


sudo journalctl -u k3s-agent -n 100

# check the status of the agent
sudo systemctl status k3s-agent.service

# check the logs of the agent
sudo journalctl -xeu k3s-agent.service
