#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for root privileges
if [ "$(id -u)" -eq 0 ]; then
  echo -e "${RED}This script must NOT be run as root.${NC}"
  echo -e "${YELLOW}Please run this script as a non-root user.${NC}"
  echo -e "${YELLOW}If you need to run minikube commands that require root privileges,${NC}"
  echo -e "${YELLOW}the script will prompt you for sudo access when needed.${NC}"
  exit 1
fi

# Default values
MINIKUBE_DRIVER="docker"
CNI_PLUGIN="calico"
VLAN_ID=100
SUBNET="10.100.0.0/24"
GATEWAY="10.100.0.1"
# Default to en0 for macOS, eth0 for Linux
if [[ "$(uname)" == "Darwin" ]]; then
  MASTER_INTERFACE="en0"
else
  MASTER_INTERFACE="eth0"
fi
MTU=1500

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$(dirname "${SCRIPT_DIR}")/.." && pwd)"
SOCNI_DIR="${WORKSPACE_DIR}/socni"

# Display banner
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI CNI Plugin Installation Script         ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
  echo -e "${YELLOW}Checking prerequisites...${NC}"
  
  if ! command -v minikube >/dev/null 2>&1; then
    echo -e "${RED}Minikube is not installed. Please install it first.${NC}"
    exit 1
  fi
  
  if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
    exit 1
  fi
  
  if [ ! -d "${SOCNI_DIR}" ]; then
    echo -e "${RED}SOCNI directory not found at ${SOCNI_DIR}.${NC}"
    exit 1
  fi

  # Check for make and build target
  if ! command -v make >/dev/null 2>&1; then
    echo -e "${RED}make is not installed. Please install it first.${NC}"
    exit 1
  fi

  cd "${SOCNI_DIR}"
  if ! make -n build >/dev/null 2>&1; then
    echo -e "${RED}build target not found in Makefile.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}All prerequisites are satisfied.${NC}"
}

# Function to start Minikube
start_minikube() {
  echo -e "${YELLOW}Starting Minikube with ${MINIKUBE_DRIVER} driver and ${CNI_PLUGIN} CNI...${NC}"
  
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
  
  minikube start --driver="$MINIKUBE_DRIVER" --network-plugin=cni --cni="$CNI_PLUGIN"
  
  if ! minikube status | grep -q "Running"; then
    echo -e "${RED}Failed to start Minikube.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Minikube started successfully.${NC}"
}

# Function to build CNI plugin
build_cni_plugin() {
  echo -e "${YELLOW}Building SOCNI CNI plugin...${NC}"
  
  cd "${SOCNI_DIR}"
  make build
  
  if [ ! -f "bin/vlan" ]; then
    echo -e "${RED}Failed to build CNI plugin.${NC}"
    exit 1
  fi

  # Verify the binary is executable
  if [ ! -x "bin/vlan" ]; then
    echo -e "${YELLOW}Making CNI plugin binary executable...${NC}"
    chmod +x bin/vlan
  fi
  
  echo -e "${GREEN}CNI plugin built successfully.${NC}"
}

# Function to install CNI plugin
install_cni_plugin() {
  echo -e "${YELLOW}Installing CNI plugin in Minikube...${NC}"
  
  cd "${SOCNI_DIR}"
  
  # Create CNI bin directory if it doesn't exist
  echo -e "${YELLOW}Creating CNI bin directory...${NC}"
  if ! minikube ssh "sudo mkdir -p /opt/cni/bin"; then
    echo -e "${RED}Failed to create CNI bin directory.${NC}"
    exit 1
  fi
  
  # Copy the CNI plugin to Minikube
  echo -e "${YELLOW}Copying CNI plugin binary...${NC}"
  if ! minikube cp bin/vlan minikube:/opt/cni/bin/; then
    echo -e "${RED}Failed to copy CNI plugin binary.${NC}"
    exit 1
  fi
  
  # Make the binary executable
  echo -e "${YELLOW}Setting executable permissions...${NC}"
  if ! minikube ssh "sudo chmod +x /opt/cni/bin/vlan"; then
    echo -e "${RED}Failed to set executable permissions.${NC}"
    exit 1
  fi
  
  # Create CNI configuration directory if it doesn't exist
  echo -e "${YELLOW}Creating CNI configuration directory...${NC}"
  if ! minikube ssh "sudo mkdir -p /etc/cni/net.d"; then
    echo -e "${RED}Failed to create CNI configuration directory.${NC}"
    exit 1
  fi
  
  # Create CNI configuration
  echo -e "${YELLOW}Creating CNI configuration...${NC}"
  # First, create a temporary file with the configuration
  TMP_CONF=$(mktemp)
  cat > "$TMP_CONF" << EOF
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

  # Copy the configuration file to Minikube
  if ! minikube cp "$TMP_CONF" minikube:/etc/cni/net.d/10-socni.conflist; then
    echo -e "${RED}Failed to copy CNI configuration.${NC}"
    rm "$TMP_CONF"
    exit 1
  fi

  # Clean up temporary file
  rm "$TMP_CONF"

  # Verify the configuration was written
  if ! minikube ssh "test -f /etc/cni/net.d/10-socni.conflist"; then
    echo -e "${RED}Failed to create CNI configuration.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}CNI plugin installed successfully.${NC}"
}

# Function to deploy CNI plugin
deploy_cni_plugin() {
  echo -e "${YELLOW}Deploying CNI plugin to Minikube...${NC}"
  
  cd "${SOCNI_DIR}"
  
  if [ ! -f "manifests/daemonset.yaml" ]; then
    echo -e "${RED}DaemonSet manifest not found.${NC}"
    exit 1
  fi
  
  # Deploy the DaemonSet
  make deploy

  # Wait for pods to be ready with more detailed status
  echo -e "${YELLOW}Waiting for CNI plugin pods to be ready...${NC}"
  echo -e "${YELLOW}This may take a few minutes...${NC}"
  
  # Increase timeout to 5 minutes
  TIMEOUT=300
  INTERVAL=10
  ELAPSED=0
  
  while [ $ELAPSED -lt $TIMEOUT ]; do
    # Get pod status
    POD_STATUS=$(kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    POD_CONDITIONS=$(kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].status.conditions[*].type}' 2>/dev/null)
    POD_NODE=$(kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null)
    
    if [ "$POD_STATUS" = "Running" ]; then
      echo -e "${GREEN}CNI plugin pods are running.${NC}"
      break
    fi
    
    echo -e "${YELLOW}Current pod status: ${POD_STATUS:-Unknown}${NC}"
    if [ -n "$POD_CONDITIONS" ]; then
      echo -e "${YELLOW}Pod conditions: ${POD_CONDITIONS}${NC}"
    fi
    if [ -n "$POD_NODE" ]; then
      echo -e "${YELLOW}Scheduled on node: ${POD_NODE}${NC}"
    fi
    
    # Show pod events
    echo -e "${YELLOW}Recent pod events:${NC}"
    kubectl get events -n kube-system --field-selector involvedObject.kind=Pod,involvedObject.name=$(kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].metadata.name}' 2>/dev/null) --sort-by='.lastTimestamp' --tail=3 2>/dev/null || true
    
    # If pod is Pending, check for specific issues
    if [ "$POD_STATUS" = "Pending" ]; then
      echo -e "${YELLOW}Checking for common Pending pod issues:${NC}"
      
      # Check for image pull issues
      IMAGE_PULL_STATUS=$(kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
      if [ "$IMAGE_PULL_STATUS" = "ImagePullBackOff" ] || [ "$IMAGE_PULL_STATUS" = "ErrImagePull" ]; then
        echo -e "${RED}Image pull issue detected: ${IMAGE_PULL_STATUS}${NC}"
        echo -e "${YELLOW}Image being pulled:${NC}"
        kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null
      fi
      
      # Check for resource issues
      echo -e "${YELLOW}Node resources:${NC}"
      kubectl describe node minikube | grep -A 5 "Allocated resources:"
      
      # Check for taints and tolerations
      echo -e "${YELLOW}Node taints:${NC}"
      kubectl describe node minikube | grep Taints
      echo -e "${YELLOW}Pod tolerations:${NC}"
      kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].spec.tolerations}' 2>/dev/null
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo -e "${RED}Timeout waiting for CNI plugin pods to be ready.${NC}"
      echo -e "${YELLOW}Checking pod details for troubleshooting:${NC}"
      kubectl describe pods -n kube-system -l app=vlan-cni
      echo -e "${YELLOW}Checking daemonset details:${NC}"
      kubectl describe daemonset vlan-cni-installer -n kube-system
      exit 1
    fi
  done
  
  echo -e "${GREEN}CNI plugin deployed successfully.${NC}"
}

# Function to verify installation
verify_installation() {
  echo -e "${YELLOW}Verifying CNI plugin installation...${NC}"
  
  if ! kubectl get pods -n kube-system | grep -q "vlan-cni"; then
    echo -e "${RED}CNI plugin pods are not running.${NC}"
    exit 1
  fi

  # Check pod status
  POD_STATUS=$(kubectl get pods -n kube-system -l app=vlan-cni -o jsonpath='{.items[0].status.phase}')
  if [ "$POD_STATUS" != "Running" ]; then
    echo -e "${RED}CNI plugin pod is not running. Status: $POD_STATUS${NC}"
    exit 1
  fi
  
  echo -e "${YELLOW}CNI plugin logs:${NC}"
  kubectl logs -n kube-system -l app=vlan-cni --tail=10
  
  echo -e "${GREEN}CNI plugin installation verified successfully.${NC}"
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
      --help)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --driver DRIVER       Minikube driver (default: docker)"
        echo "  --cni PLUGIN          CNI plugin (default: calico)"
        echo "  --vlan-id ID          VLAN ID (default: 100)"
        echo "  --subnet SUBNET       Subnet for VLAN (default: 10.100.0.0/24)"
        echo "  --gateway GATEWAY     Gateway for VLAN (default: 10.100.0.1)"
        echo "  --master INTERFACE    Master interface for VLAN (default: en0 for macOS, eth0 for Linux)"
        echo "  --mtu MTU             MTU for VLAN (default: 1500)"
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
  build_cni_plugin
  install_cni_plugin
  deploy_cni_plugin
  verify_installation
  
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${BLUE}         SOCNI CNI Plugin Installation Complete      ${NC}"
  echo -e "${BLUE}======================================================${NC}"
}

# Run the main function
main "$@" 