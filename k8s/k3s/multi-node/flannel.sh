sudo mkdir -p /run/flannel
sudo tee /run/flannel/subnet.env > /dev/null << EOF
FLANNEL_NETWORK=10.42.0.0/16
FLANNEL_SUBNET=10.42.1.0/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
EOF