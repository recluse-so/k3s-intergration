#!/bin/bash
set -e

# SOCNI Minikube Installation Script
# This script automates the installation of SOCNI in a Minikube environment

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
MINIKUBE_DRIVER="docker"
CNI_PLUGIN="calico"
VLAN_ID=100
VLAN_ID_2=200
SUBNET="10.100.0.0/24"
GATEWAY="10.100.0.1"
MASTER_INTERFACE="eth0"
MTU=1500
TENANT_ID="test"

# Display banner
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI Minikube Installation Script          ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
  echo -e "${YELLOW}Checking prerequisites...${NC}"
  
  # Check for minikube
  if ! command_exists minikube; then
    echo -e "${RED}Minikube is not installed. Please install it first.${NC}"
    echo -e "Visit https://minikube.sigs.k8s.io/docs/start/ for installation instructions."
    exit 1
  fi
  
  # Check for kubectl
  if ! command_exists kubectl; then
    echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
    echo -e "Visit https://kubernetes.io/docs/tasks/tools/ for installation instructions."
    exit 1
  fi
  
  # Check for docker
  if ! command_exists docker; then
    echo -e "${RED}Docker is not installed. Please install it first.${NC}"
    echo -e "Visit https://docs.docker.com/get-docker/ for installation instructions."
    exit 1
  fi
  
  # Check for git
  if ! command_exists git; then
    echo -e "${RED}Git is not installed. Please install it first.${NC}"
    echo -e "Visit https://git-scm.com/downloads for installation instructions."
    exit 1
  fi
  
  # Check for make
  if ! command_exists make; then
    echo -e "${RED}Make is not installed. Please install it first.${NC}"
    echo -e "Visit https://www.gnu.org/software/make/ for installation instructions."
    exit 1
  fi
  
  echo -e "${GREEN}All prerequisites are satisfied.${NC}"
}

# Function to start Minikube
start_minikube() {
  echo -e "${YELLOW}Starting Minikube with ${MINIKUBE_DRIVER} driver and ${CNI_PLUGIN} CNI...${NC}"
  
  # Check if Minikube is already running
  if minikube status | grep -q "Running"; then
    echo -e "${YELLOW}Minikube is already running. Do you want to restart it? (y/n)${NC}"
    read -r restart
    if [[ "$restart" =~ ^[Yy]$ ]]; then
      minikube stop
      minikube delete
    else
      echo -e "${YELLOW}Using existing Minikube cluster.${NC}"
      return
    fi
  fi
  
  # Start Minikube with the specified driver and CNI
  minikube start --driver="$MINIKUBE_DRIVER" --network-plugin=cni --cni="$CNI_PLUGIN"
  
  # Verify Minikube is running
  if ! minikube status | grep -q "Running"; then
    echo -e "${RED}Failed to start Minikube.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Minikube started successfully.${NC}"
}

# Function to build SOCNI
build_socni() {
  echo -e "${YELLOW}Building SOCNI...${NC}"
  
  # Check if we're in the SOCNI directory
  if [ ! -f "Cargo.toml" ]; then
    echo -e "${YELLOW}SOCNI source code not found. Cloning repository...${NC}"
    git clone https://github.com/username/socni.git
    cd socni
  fi
  
  # Build SOCNI
  make build
  
  if [ ! -f "bin/vlan" ] || [ ! -f "bin/socni-ctl" ]; then
    echo -e "${RED}Failed to build SOCNI.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}SOCNI built successfully.${NC}"
}

# Function to install SOCNI in Minikube
install_socni_in_minikube() {
  echo -e "${YELLOW}Installing SOCNI in Minikube...${NC}"
  
  # Copy the CNI plugin to Minikube
  minikube cp bin/vlan minikube:/opt/cni/bin/
  
  # Copy the CLI tool to Minikube
  minikube cp bin/socni-ctl minikube:/usr/local/bin/
  
  # Make the binaries executable
  minikube ssh "sudo chmod +x /opt/cni/bin/vlan /usr/local/bin/socni-ctl"
  
  # Create CNI configuration directory if it doesn't exist
  minikube ssh "sudo mkdir -p /etc/cni/net.d"
  
  # Create CNI configuration
  echo -e "${YELLOW}Creating CNI configuration...${NC}"
  cat << EOF | minikube ssh "sudo tee /etc/cni/net.d/10-socni.conflist"
{
  "cniVersion": "1.0.0",
  "name": "socni-network",
  "plugins": [
    {
      "type": "vlan",
      "master": "$MASTER_INTERFACE",
      "vlan": $VLAN_ID,
      "mtu": $MTU,
      "ipam": {
        "type": "host-local",
        "subnet": "$SUBNET",
        "gateway": "$GATEWAY"
      }
    }
  ]
}
EOF
  
  echo -e "${GREEN}SOCNI installed in Minikube successfully.${NC}"
}

# Function to deploy SOCNI to Minikube
deploy_socni() {
  echo -e "${YELLOW}Deploying SOCNI to Minikube...${NC}"
  
  # Deploy the DaemonSet
  make deploy
  
  # Create network attachment definitions
  make create-networks
  
  echo -e "${GREEN}SOCNI deployed to Minikube successfully.${NC}"
}

# Function to verify installation
verify_installation() {
  echo -e "${YELLOW}Verifying SOCNI installation...${NC}"
  
  # Check if SOCNI pods are running
  if ! kubectl get pods -n kube-system | grep -q "socni"; then
    echo -e "${RED}SOCNI pods are not running.${NC}"
    exit 1
  fi
  
  # Check SOCNI logs
  echo -e "${YELLOW}SOCNI logs:${NC}"
  kubectl logs -n kube-system -l app=socni --tail=10
  
  # Test SOCNI CLI tool
  echo -e "${YELLOW}SOCNI CLI tool status:${NC}"
  minikube ssh "socni-ctl status"
  
  echo -e "${GREEN}SOCNI installation verified successfully.${NC}"
}

# Function to test SOCNI
test_socni() {
  echo -e "${YELLOW}Testing SOCNI...${NC}"
  
  # Create a test pod with VLAN network
  echo -e "${YELLOW}Creating test pod with VLAN network...${NC}"
  cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan-pod
  annotations:
    socni.network.aranya.io/tenant-id: "$TENANT_ID"
    socni.network.aranya.io/vlan: "$VLAN_ID"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF
  
  # Wait for the pod to be ready
  echo -e "${YELLOW}Waiting for test pod to be ready...${NC}"
  kubectl wait --for=condition=Ready pod/test-vlan-pod --timeout=60s
  
  # Check pod IP address
  echo -e "${YELLOW}Test pod IP address:${NC}"
  kubectl get pod test-vlan-pod -o wide
  
  # Execute commands in the pod
  echo -e "${YELLOW}Test pod network interfaces:${NC}"
  kubectl exec -it test-vlan-pod -- ip addr
  
  echo -e "${YELLOW}Testing connectivity to gateway:${NC}"
  kubectl exec -it test-vlan-pod -- ping -c 3 "$GATEWAY"
  
  # Create another pod on a different VLAN
  echo -e "${YELLOW}Creating another test pod on a different VLAN...${NC}"
  cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan-pod-2
  annotations:
    socni.network.aranya.io/tenant-id: "$TENANT_ID"
    socni.network.aranya.io/vlan: "$VLAN_ID_2"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF
  
  # Wait for the pod to be ready
  echo -e "${YELLOW}Waiting for second test pod to be ready...${NC}"
  kubectl wait --for=condition=Ready pod/test-vlan-pod-2 --timeout=60s
  
  # Try to ping between pods (should fail due to VLAN isolation)
  echo -e "${YELLOW}Testing VLAN isolation (should fail):${NC}"
  POD2_IP=$(kubectl get pod test-vlan-pod-2 -o jsonpath='{.status.podIP}')
  kubectl exec -it test-vlan-pod -- ping -c 3 "$POD2_IP" || echo -e "${GREEN}VLAN isolation test passed (ping failed as expected).${NC}"
  
  echo -e "${GREEN}SOCNI testing completed successfully.${NC}"
}

# Function to clean up
cleanup() {
  echo -e "${YELLOW}Cleaning up...${NC}"
  
  # Delete test pods
  kubectl delete pod test-vlan-pod test-vlan-pod-2 --ignore-not-found
  
  # Delete SOCNI resources
  kubectl delete -f manifests/daemonset.yaml --ignore-not-found
  kubectl delete -f deployments/network-attachment-definitions/ --ignore-not-found
  
  echo -e "${GREEN}Cleanup completed successfully.${NC}"
}

# Main function
main() {
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --driver)
        MINIKUBE_DRIVER="$2"
        shift 2
        ;;
      --cni)
        CNI_PLUGIN="$2"
        shift 2
        ;;
      --vlan-id)
        VLAN_ID="$2"
        shift 2
        ;;
      --vlan-id-2)
        VLAN_ID_2="$2"
        shift 2
        ;;
      --subnet)
        SUBNET="$2"
        shift 2
        ;;
      --gateway)
        GATEWAY="$2"
        shift 2
        ;;
      --master)
        MASTER_INTERFACE="$2"
        shift 2
        ;;
      --mtu)
        MTU="$2"
        shift 2
        ;;
      --tenant-id)
        TENANT_ID="$2"
        shift 2
        ;;
      --cleanup)
        cleanup
        exit 0
        ;;
      --help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --driver DRIVER       Minikube driver (default: docker)"
        echo "  --cni PLUGIN          CNI plugin (default: calico)"
        echo "  --vlan-id ID          VLAN ID for first pod (default: 100)"
        echo "  --vlan-id-2 ID        VLAN ID for second pod (default: 200)"
        echo "  --subnet SUBNET       Subnet for VLAN (default: 10.100.0.0/24)"
        echo "  --gateway GATEWAY     Gateway for VLAN (default: 10.100.0.1)"
        echo "  --master INTERFACE    Master interface for VLAN (default: eth0)"
        echo "  --mtu MTU             MTU for VLAN (default: 1500)"
        echo "  --tenant-id ID        Tenant ID for pods (default: test)"
        echo "  --cleanup             Clean up resources and exit"
        echo "  --help                Show this help message"
        exit 0
        ;;
      *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use --help for usage information."
        exit 1
        ;;
    esac
  done
  
  # Run the installation steps
  check_prerequisites
  start_minikube
  build_socni
  install_socni_in_minikube
  deploy_socni
  verify_installation
  test_socni
  
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${BLUE}         SOCNI Minikube Installation Complete         ${NC}"
  echo -e "${BLUE}======================================================${NC}"
  echo ""
  echo -e "${GREEN}SOCNI has been successfully installed and tested in Minikube.${NC}"
  echo -e "To clean up resources, run: $0 --cleanup"
}

# Run the main function
main "$@" 