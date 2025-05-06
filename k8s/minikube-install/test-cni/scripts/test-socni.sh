#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$(cd "${SCRIPT_DIR}/../manifests" && pwd)"
PLUGIN_INSTALL_DIR="${MANIFESTS_DIR}/plugin-install"
POLICY_DIR="${MANIFESTS_DIR}/policy"

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI CNI Plugin Test Script               ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v kubectl >/dev/null 2>&1; then
        echo -e "${RED}kubectl is not installed. Please install it first.${NC}"
        exit 1
    fi
    
    # Check if Multus is installed
    echo -e "${YELLOW}Checking Multus CNI installation...${NC}"
    if ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
        echo -e "${YELLOW}Multus CNI is not installed. Installing now...${NC}"
        kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
        
        # Wait for Multus to be ready with timeout
        echo -e "${YELLOW}Waiting for Multus to be ready (timeout: 60s)...${NC}"
        TIMEOUT=60
        INTERVAL=5
        ELAPSED=0
        
        while [ $ELAPSED -lt $TIMEOUT ]; do
            if kubectl get pods -n kube-system -l app=multus | grep -q "Running"; then
                echo -e "${GREEN}Multus CNI is ready.${NC}"
                break
            fi
            
            echo -e "${YELLOW}Waiting for Multus pods to be ready... (${ELAPSED}s elapsed)${NC}"
            kubectl get pods -n kube-system -l app=multus
            
            sleep $INTERVAL
            ELAPSED=$((ELAPSED + INTERVAL))
            
            if [ $ELAPSED -ge $TIMEOUT ]; then
                echo -e "${RED}Timeout waiting for Multus to be ready.${NC}"
                echo -e "${YELLOW}Checking Multus pod status:${NC}"
                kubectl describe pods -n kube-system -l app=multus
                exit 1
            fi
        done
    else
        echo -e "${GREEN}Multus CNI is already installed.${NC}"
    fi
    
    echo -e "${GREEN}All prerequisites are satisfied.${NC}"
}

# Function to deploy test resources
deploy_test_resources() {
    echo -e "${YELLOW}Deploying test resources...${NC}"
    
    # Create main RBAC resources
    echo -e "${YELLOW}Creating main RBAC resources...${NC}"
    if ! kubectl apply -f "${PLUGIN_INSTALL_DIR}/socni-rbac.yaml"; then
        echo -e "${RED}Failed to create main RBAC resources.${NC}"
        exit 1
    fi
    
    # Create policy RBAC resources
    echo -e "${YELLOW}Creating policy RBAC resources...${NC}"
    if ! kubectl apply -f "${POLICY_DIR}/socni-policy-rbac.yaml"; then
        echo -e "${RED}Failed to create policy RBAC resources.${NC}"
        exit 1
    fi
    
    # Create ConfigMap
    echo -e "${YELLOW}Creating ConfigMap...${NC}"
    if ! kubectl apply -f "${PLUGIN_INSTALL_DIR}/socni-configmap.yaml"; then
        echo -e "${RED}Failed to create ConfigMap.${NC}"
        exit 1
    fi
    
    # Create policies secret
    echo -e "${YELLOW}Creating policies secret...${NC}"
    if ! kubectl create secret generic socni-policies \
        --from-file="${POLICY_DIR}/multi-tenant-policy.md" \
        --namespace=kube-system \
        --dry-run=client -o yaml | kubectl apply -f -; then
        echo -e "${RED}Failed to create policies secret.${NC}"
        exit 1
    fi
    
    # Create NetworkAttachmentDefinition
    echo -e "${YELLOW}Creating NetworkAttachmentDefinition...${NC}"
    if ! kubectl apply -f "${PLUGIN_INSTALL_DIR}/socni-network-attachment-definition.yaml"; then
        echo -e "${RED}Failed to create NetworkAttachmentDefinition.${NC}"
        exit 1
    fi
    
    # Create SOCNI DaemonSet
    echo -e "${YELLOW}Creating SOCNI DaemonSet...${NC}"
    if ! kubectl apply -f "${PLUGIN_INSTALL_DIR}/socni-daemonset.yaml"; then
        echo -e "${RED}Failed to create SOCNI DaemonSet.${NC}"
        exit 1
    fi
    
    # Wait for SOCNI DaemonSet to be ready
    echo -e "${YELLOW}Waiting for SOCNI DaemonSet to be ready...${NC}"
    TIMEOUT=60
    INTERVAL=5
    ELAPSED=0
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if kubectl get pods -n kube-system -l app=socni | grep -q "Running"; then
            echo -e "${GREEN}SOCNI DaemonSet is ready.${NC}"
            break
        fi
        
        echo -e "${YELLOW}Waiting for SOCNI pods to be ready... (${ELAPSED}s elapsed)${NC}"
        kubectl get pods -n kube-system -l app=socni
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo -e "${RED}Timeout waiting for SOCNI DaemonSet to be ready.${NC}"
            echo -e "${YELLOW}Checking SOCNI pod status:${NC}"
            kubectl describe pods -n kube-system -l app=socni
            exit 1
        fi
    done
    
    # Create test pod
    echo -e "${YELLOW}Creating test pod...${NC}"
    if ! kubectl apply -f "${PLUGIN_INSTALL_DIR}/socni-example-pod.yaml"; then
        echo -e "${RED}Failed to create test pod.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Test resources deployed successfully.${NC}"
}

# Function to verify test setup
verify_test_setup() {
    echo -e "${YELLOW}Verifying test setup...${NC}"
    
    # Wait for pod to be ready with timeout
    echo -e "${YELLOW}Waiting for test pod to be ready (timeout: 60s)...${NC}"
    TIMEOUT=60
    INTERVAL=5
    ELAPSED=0
    
    while [ $ELAPSED -lt $TIMEOUT ]; do
        POD_STATUS=$(kubectl get pod socni-example -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$POD_STATUS" = "Running" ]; then
            echo -e "${GREEN}Test pod is ready.${NC}"
            break
        fi
        
        echo -e "${YELLOW}Current pod status: ${POD_STATUS:-Unknown} (${ELAPSED}s elapsed)${NC}"
        kubectl get pod socni-example
        
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo -e "${RED}Timeout waiting for test pod to be ready.${NC}"
            echo -e "${YELLOW}Checking pod details:${NC}"
            kubectl describe pod socni-example
            exit 1
        fi
    done
    
    # Get pod details
    echo -e "${YELLOW}Pod details:${NC}"
    kubectl get pod socni-example -o wide
    
    # Get network attachment details
    echo -e "${YELLOW}Network attachment details:${NC}"
    kubectl get network-attachment-definitions.k8s.cni.cncf.io socni-vlan -n kube-system
    
    # Check pod network interfaces
    echo -e "${YELLOW}Pod network interfaces:${NC}"
    if ! kubectl exec socni-example -- ip addr; then
        echo -e "${RED}Failed to get pod network interfaces.${NC}"
        exit 1
    fi
    
    # Test network connectivity with timeout
    echo -e "${YELLOW}Testing network connectivity...${NC}"
    if ! kubectl exec socni-example -- ping -c 4 -W 5 8.8.8.8; then
        echo -e "${RED}Network connectivity test failed.${NC}"
        echo -e "${YELLOW}Checking pod network configuration:${NC}"
        kubectl exec socni-example -- ip route
        exit 1
    fi
    
    echo -e "${GREEN}Test setup verified successfully.${NC}"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
    
    # Run the test steps
    check_prerequisites
    deploy_test_resources
    verify_test_setup
    
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}         SOCNI CNI Plugin Test Complete            ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${YELLOW}To clean up test resources, run: ./cleanup-socni.sh${NC}"
}

# Run the main function
main "$@" 