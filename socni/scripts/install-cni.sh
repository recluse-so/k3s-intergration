#!/bin/bash
set -e

# SOCNI Kubernetes Installation Script
# This script installs SOCNI in a Kubernetes environment

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCNI_DIR="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="$SOCNI_DIR/manifests"

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Display banner
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI Kubernetes Installation Script         ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Create log file
LOG_FILE=/var/log/socni-k8s-install.log
echo "Starting SOCNI Kubernetes installation at $(date)" > $LOG_FILE

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}kubectl is not installed or not in PATH${NC}"
  echo "ERROR: kubectl is not installed or not in PATH" >> $LOG_FILE
  exit 1
fi

# Check if we can connect to the Kubernetes cluster
if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}Cannot connect to Kubernetes cluster${NC}"
  echo "ERROR: Cannot connect to Kubernetes cluster" >> $LOG_FILE
  exit 1
fi

# Install Multus CNI plugin
echo -e "${GREEN}Installing Multus CNI plugin...${NC}"
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
echo "Installed Multus CNI plugin" >> $LOG_FILE

# Wait for Multus to be ready
echo -e "${GREEN}Waiting for Multus to be ready...${NC}"
kubectl rollout status daemonset/kube-multus-ds -n kube-system
echo "Multus is ready" >> $LOG_FILE

# Build the binaries if needed
if [ ! -f "$SOCNI_DIR/bin/vlan" ] || [ ! -f "$SOCNI_DIR/bin/socni-ctl" ]; then
  echo -e "${YELLOW}Binaries not found. Building SOCNI...${NC}"
  cd "$SOCNI_DIR"
  cargo build --release
  mkdir -p bin
  cp ./target/release/socni bin/vlan
  cp ./target/release/socni-ctl bin/socni-ctl
  chmod +x bin/vlan bin/socni-ctl
  echo "Built SOCNI binaries" >> $LOG_FILE
fi

# Create default CNI configuration
echo -e "${GREEN}Creating default CNI configuration...${NC}"
cat > /tmp/10-vlan.conflist << EOF
{
  "cniVersion": "1.0.0",
  "name": "vlan-cni",
  "plugins": [
    {
      "type": "vlan",
      "master": "eth0",
      "vlan": 100,
      "ipam": {
        "type": "host-local",
        "subnet": "10.10.0.0/24"
      }
    }
  ]
}
EOF

kubectl create configmap socni-cni-config --from-file=/tmp/10-vlan.conflist -o yaml --dry-run=client | kubectl apply -f -
echo "Created ConfigMap with CNI configuration" >> $LOG_FILE

# Create the DaemonSet
echo -e "${GREEN}Deploying SOCNI DaemonSet...${NC}"
if [ -f "$MANIFESTS_DIR/daemonset.yaml" ]; then
  kubectl apply -f "$MANIFESTS_DIR/daemonset.yaml"
  echo "Deployed SOCNI DaemonSet from $MANIFESTS_DIR/daemonset.yaml" >> $LOG_FILE
else
  # Create a basic DaemonSet if the manifest doesn't exist
  cat > /tmp/socni-daemonset.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: socni-installer
  namespace: kube-system
  labels:
    app: socni-installer
spec:
  selector:
    matchLabels:
      app: socni-installer
  template:
    metadata:
      labels:
        app: socni-installer
    spec:
      containers:
      - name: socni-installer
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
        - |
          mkdir -p /opt/cni/bin /etc/cni/net.d
          cp /socni-cni-config/10-vlan.conflist /etc/cni/net.d/
          while true; do sleep 3600; done
        volumeMounts:
        - name: cni-config
          mountPath: /socni-cni-config
        - name: cni-bin-dir
          mountPath: /opt/cni/bin
        - name: cni-conf-dir
          mountPath: /etc/cni/net.d
        - name: cni-binary
          mountPath: /socni-binary
      volumes:
      - name: cni-config
        configMap:
          name: socni-cni-config
      - name: cni-bin-dir
        hostPath:
          path: /opt/cni/bin
      - name: cni-conf-dir
        hostPath:
          path: /etc/cni/net.d
      - name: cni-binary
        hostPath:
          path: $SOCNI_DIR/bin
EOF
  kubectl apply -f /tmp/socni-daemonset.yaml
  echo "Created and deployed basic SOCNI DaemonSet" >> $LOG_FILE
fi

# Wait for Multus CRDs to be ready
echo -e "${GREEN}Waiting for Multus CRDs to be ready...${NC}"
kubectl wait --for=condition=established --timeout=60s crd/network-attachment-definitions.k8s.cni.cncf.io
echo "Multus CRDs are ready" >> $LOG_FILE

# Create network attachment definitions
echo -e "${GREEN}Creating network attachment definitions...${NC}"
if [ -d "$MANIFESTS_DIR/network-attachment-definitions" ]; then
  # Create namespace if it doesn't exist
  kubectl create namespace secure-zone-1 --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$MANIFESTS_DIR/network-attachment-definitions/"
  echo "Created network attachment definitions" >> $LOG_FILE
else
  # Create namespace if it doesn't exist
  kubectl create namespace secure-zone-1 --dry-run=client -o yaml | kubectl apply -f -
  
  # Create a basic network attachment definition if the directory doesn't exist
  cat > /tmp/vlan100.yaml << EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vlan100
  namespace: secure-zone-1
spec:
  config: '{
    "type": "vlan",
    "master": "eth0",
    "vlan": 100,
    "ipam": {
      "type": "host-local",
      "subnet": "10.10.0.0/24"
    }
  }'
EOF
  kubectl apply -f /tmp/vlan100.yaml
  echo "Created basic network attachment definition" >> $LOG_FILE
fi

# Wait for the DaemonSet to be ready
echo -e "${GREEN}Waiting for SOCNI DaemonSet to be ready...${NC}"
# First check if the DaemonSet exists
if kubectl get daemonset socni-installer -n kube-system &> /dev/null; then
  kubectl rollout status daemonset/socni-installer -n kube-system
  echo "SOCNI DaemonSet is ready" >> $LOG_FILE
else
  echo -e "${YELLOW}Warning: SOCNI DaemonSet not found. This might be normal if it's still being created.${NC}"
  echo "Warning: SOCNI DaemonSet not found" >> $LOG_FILE
fi

# Label the nodes
echo -e "${GREEN}Labeling nodes with VLAN capability...${NC}"
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label node $node --overwrite vlan.cni.kubernetes.io/enabled=true
  kubectl label node $node --overwrite vlan.cni.kubernetes.io/vlan-100=true
  echo "Labeled node $node with VLAN capability" >> $LOG_FILE
done

echo -e "${GREEN}SOCNI Kubernetes installation complete!${NC}"
echo "Installation completed at $(date)" >> $LOG_FILE

# Final message
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}SOCNI Kubernetes installation completed successfully!${NC}"
echo -e "${GREEN}===============================================${NC}"
echo ""
echo -e "${YELLOW}To verify the installation:${NC}"
echo -e "${BLUE}kubectl get pods -n kube-system | grep socni-installer${NC}"
echo -e "${BLUE}kubectl get network-attachment-definitions -n secure-zone-1${NC}"
echo ""
echo -e "${YELLOW}To create a pod with VLAN access:${NC}"
echo -e "${BLUE}kubectl run test-pod -n secure-zone-1 --image=busybox --overrides='{\"spec\":{\"annotations\":{\"k8s.v1.cni.cncf.io/networks\":\"vlan100\"}}}' -- sleep 3600${NC}"
echo "" 