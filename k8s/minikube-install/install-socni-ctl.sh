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
WORKSPACE_DIR="$(cd "$(dirname "${SCRIPT_DIR}")/.." && pwd)"
SOCNI_DIR="${WORKSPACE_DIR}/socni"

# Display banner
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI Control Tool Installation Script       ${NC}"
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

# Function to build control tool
build_control_tool() {
  echo -e "${YELLOW}Building SOCNI control tool...${NC}"
  
  cd "${SOCNI_DIR}"
  make build
  
  if [ ! -f "bin/socni-ctl" ]; then
    echo -e "${RED}Failed to build control tool.${NC}"
    exit 1
  fi

  # Verify the binary is executable
  if [ ! -x "bin/socni-ctl" ]; then
    echo -e "${YELLOW}Making control tool binary executable...${NC}"
    chmod +x bin/socni-ctl
  fi
  
  echo -e "${GREEN}Control tool built successfully.${NC}"
}

# Function to install control tool
install_control_tool() {
  echo -e "${YELLOW}Installing control tool in Minikube...${NC}"
  
  cd "${SOCNI_DIR}"
  
  # Create directory if it doesn't exist
  minikube ssh "sudo mkdir -p /usr/local/bin"
  
  # Copy the control tool to Minikube
  minikube cp bin/socni-ctl minikube:/usr/local/bin/
  
  # Make the binary executable
  minikube ssh "sudo chmod +x /usr/local/bin/socni-ctl"

  # Verify the binary was copied
  if ! minikube ssh "test -f /usr/local/bin/socni-ctl"; then
    echo -e "${RED}Failed to copy control tool to Minikube.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Control tool installed successfully.${NC}"
}

# Function to verify installation
verify_installation() {
  echo -e "${YELLOW}Verifying control tool installation...${NC}"
  
  if ! minikube ssh "which socni-ctl" >/dev/null 2>&1; then
    echo -e "${RED}Control tool is not installed.${NC}"
    exit 1
  fi

  # Check if the binary is executable
  if ! minikube ssh "test -x /usr/local/bin/socni-ctl"; then
    echo -e "${RED}Control tool is not executable.${NC}"
    exit 1
  fi
  
  echo -e "${YELLOW}Control tool version:${NC}"
  if ! minikube ssh "socni-ctl --version"; then
    echo -e "${RED}Failed to get control tool version.${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Control tool installation verified successfully.${NC}"
}

# Main function
main() {
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --help)
        echo "Usage: $0 [options]"
        echo "Options:"
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
  build_control_tool
  install_control_tool
  verify_installation
  
  echo -e "${BLUE}======================================================${NC}"
  echo -e "${BLUE}         SOCNI Control Tool Installation Complete    ${NC}"
  echo -e "${BLUE}======================================================${NC}"
}

# Run the main function
main "$@" 