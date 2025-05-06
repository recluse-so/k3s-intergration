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

export TOKEN_AGENT=K10c258d58b2bac887fd414dd0aed3a2e151aed8de8d44ea77b1db3db4510cbdc8c::server:w4jtll371cZSu2lapTUw/amPmY4dDLek7PCAwAkRYEw=

# create a k3s agent
multipass launch --name k3sAgent --cpus 2 --memory 2G --disk 10G

# get the ip address of the k3s cluster
multipass list

# set the server ip address
export SERVER_IP=$(multipass info k3sCluster | grep IPv4 | awk '{print $2}')

# 1. Try to find the kubeconfig file
echo "Searching for kubeconfig file..."
multipass exec k3sCluster sudo find / -name "k3s.yaml" 2>/dev/null

# 2. If not found, check common locations
echo "Checking common locations..."
multipass exec k3sCluster ls -la /etc/rancher/k3s/k3s.yaml 2>/dev/null
multipass exec k3sCluster ls -la ~/.kube/config 2>/dev/null
multipass exec k3sCluster ls -la /var/lib/rancher/k3s/server/tls/ 2>/dev/null

# 3. Generate a new kubeconfig file if needed
echo "Generating new kubeconfig file..."
multipass exec k3sCluster sudo k3s kubectl config view --raw > k3s.yaml

# login to the k3s agent
# multipass shell k3sAgent
sed -i '' "s|server: https://127.0.0.1:6443|server: https://$SERVER_IP:6443|g" k3s.yaml

# 6. Set the KUBECONFIG environment variable
export KUBECONFIG=$PWD/k3s.yaml
export SERVER_IP=https://192.168.64.4:6443
SERVER_IP=$(multipass info k3sCluster | grep IPv4 | awk '{print $2}')
TOKEN=$(multipass exec k3sCluster sudo cat /var/lib/rancher/k3s/server/node-token)

echo "Server IP: $SERVER_IP"
echo "Token: $TOKEN"

# install k3s on the agent
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://192.168.64.4:6443 \
    --token K10c258d58b2bac887fd414dd0aed3a2e151aed8de8d44ea77b1db3db4510cbdc8c::server:w4jtll371cZSu2lapTUw/amPmY4dDLek7PCAwAkRYEw=" sh -

# multipass exec k3sAgent -- bash -c 'curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent" K3S_TOKEN=$TOKEN_AGENT sh -s - --server https://192.168.64.4:6443'

# Create the config directory if it doesn't exist
multipass exec k3sAgent sudo mkdir -p /etc/rancher/k3s

# Create the config file with the token and server URL
multipass exec k3sAgent sudo tee /etc/rancher/k3s/config.yaml > /dev/null << EOF
server: $SERVER_IP
token: $TOKEN_AGENT
EOF


# install k3s 
kubectl get nodes


sudo journalctl -u k3s-agent -n 100

# check the status of the agent
sudo systemctl status k3s-agent.service

# check the logs of the agent
sudo journalctl -xeu k3s-agent.service




##### ----- Remove multipass instance ----- #####
multipass delete k3sCluster
multipass delete k3sAgent
multipass purge


