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

# Function to check if a resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if [ -n "$namespace" ]; then
        kubectl get "$resource_type" "$resource_name" -n "$namespace" >/dev/null 2>&1
    else
        kubectl get "$resource_type" "$resource_name" >/dev/null 2>&1
    fi
}

# Function to delete a resource with timeout
delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=30
    local interval=5
    local elapsed=0
    
    echo -e "${YELLOW}Deleting $resource_type $resource_name...${NC}"
    
    if [ -n "$namespace" ]; then
        kubectl delete "$resource_type" "$resource_name" -n "$namespace" --grace-period=0 --force
    else
        kubectl delete "$resource_type" "$resource_name" --grace-period=0 --force
    fi
    
    while [ $elapsed -lt $timeout ]; do
        if ! resource_exists "$resource_type" "$resource_name" "$namespace"; then
            echo -e "${GREEN}$resource_type $resource_name deleted successfully.${NC}"
            return 0
        fi
        
        echo -e "${YELLOW}Waiting for $resource_type $resource_name to be deleted... (${elapsed}s elapsed)${NC}"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e "${RED}Timeout waiting for $resource_type $resource_name to be deleted.${NC}"
    return 1
}

# Function to delete resources from a manifest file
delete_from_manifest() {
    local manifest_file=$1
    local namespace=$2
    
    if [ -f "$manifest_file" ]; then
        echo -e "${YELLOW}Deleting resources from $manifest_file...${NC}"
        if [ -n "$namespace" ]; then
            kubectl delete -f "$manifest_file" -n "$namespace" --grace-period=0 --force
        else
            kubectl delete -f "$manifest_file" --grace-period=0 --force
        fi
    else
        echo -e "${RED}Manifest file not found: $manifest_file${NC}"
    fi
}

# Function to clean up resources
cleanup() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}         SOCNI CNI Plugin Cleanup Script           ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    
    # 1. Delete test pod
    delete_resource "pod" "socni-example" "default"
    
    # 2. Delete SOCNI DaemonSet and other resources
    delete_from_manifest "${PLUGIN_INSTALL_DIR}/socni-daemonset.yaml" "kube-system"
    delete_from_manifest "${PLUGIN_INSTALL_DIR}/socni-network-attachment-definition.yaml" "kube-system"
    delete_from_manifest "${PLUGIN_INSTALL_DIR}/socni-configmap.yaml" "kube-system"
    
    # 3. Delete policies secret
    delete_resource "secret" "socni-policies" "kube-system"
    
    # 4. Delete policy RBAC resources
    delete_from_manifest "${POLICY_DIR}/socni-policy-rbac.yaml" "kube-system"
    
    # 5. Delete main RBAC resources
    delete_from_manifest "${PLUGIN_INSTALL_DIR}/socni-rbac.yaml" "kube-system"
    
    echo -e "${GREEN}Cleanup completed successfully.${NC}"
}

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

# Run cleanup
cleanup 