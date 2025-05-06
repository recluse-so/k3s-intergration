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
    if ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io >/dev/null 2>&1; then
        echo -e "${YELLOW}Multus CNI is not installed. Installing now...${NC}"
        kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
        echo -e "${GREEN}Multus CNI installed successfully.${NC}"
    else
        echo -e "${GREEN}Multus CNI is already installed.${NC}"
    fi
    
    echo -e "${GREEN}All prerequisites are satisfied.${NC}"
}

# Function to deploy test resources
deploy_test_resources() {
    echo -e "${YELLOW}Deploying test resources...${NC}"
    
    # Create NetworkAttachmentDefinition
    echo -e "${YELLOW}Creating NetworkAttachmentDefinition...${NC}"
    kubectl apply -f "${MANIFESTS_DIR}/socni-network-attachment-definition.yaml"
    
    # Create test pod
    echo -e "${YELLOW}Creating test pod...${NC}"
    kubectl apply -f "${MANIFESTS_DIR}/socni-example-pod.yaml"
    
    echo -e "${GREEN}Test resources deployed successfully.${NC}"
}

# Function to verify test setup
verify_test_setup() {
    echo -e "${YELLOW}Verifying test setup...${NC}"
    
    # Wait for pod to be ready
    echo -e "${YELLOW}Waiting for test pod to be ready...${NC}"
    kubectl wait --for=condition=Ready pod/socni-example --timeout=60s
    
    # Get pod details
    echo -e "${YELLOW}Pod details:${NC}"
    kubectl get pod socni-example -o wide
    
    # Get network attachment details
    echo -e "${YELLOW}Network attachment details:${NC}"
    kubectl get network-attachment-definitions.k8s.cni.cncf.io socni-vlan -n kube-system
    
    # Check pod network interfaces
    echo -e "${YELLOW}Pod network interfaces:${NC}"
    kubectl exec socni-example -- ip addr
    
    # Test network connectivity
    echo -e "${YELLOW}Testing network connectivity...${NC}"
    kubectl exec socni-example -- ping -c 4 8.8.8.8
    
    echo -e "${GREEN}Test setup verified successfully.${NC}"
}

# Function to clean up test resources
cleanup_test_resources() {
    echo -e "${YELLOW}Cleaning up test resources...${NC}"
    
    # Delete test pod
    echo -e "${YELLOW}Deleting test pod...${NC}"
    kubectl delete -f "${MANIFESTS_DIR}/socni-example-pod.yaml"
    
    # Delete NetworkAttachmentDefinition
    echo -e "${YELLOW}Deleting NetworkAttachmentDefinition...${NC}"
    kubectl delete -f "${MANIFESTS_DIR}/socni-network-attachment-definition.yaml"
    
    echo -e "${GREEN}Test resources cleaned up successfully.${NC}"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cleanup)
                cleanup_test_resources
                exit 0
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --cleanup    Clean up test resources"
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
    echo -e "${YELLOW}To clean up test resources, run: $0 --cleanup${NC}"
}

# Run the main function
main "$@" 