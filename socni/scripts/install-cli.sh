#!/bin/bash
set -e

# SOCNI CLI Installation Script
# This script is called by the Makefile during installation
# Note: This installation only includes the command line tool.
# The VLAN CNI plugin is not installed by this script.

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Fix: Correctly identify the socni directory
SOCNI_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$SOCNI_DIR")"

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Display banner
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI CLI Installation Script                ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""
echo -e "${YELLOW}Note: This installation only includes the command line tool.${NC}"
echo -e "${YELLOW}The VLAN CNI plugin is not installed by this script.${NC}"
echo ""

# Create log file
LOG_FILE=/var/log/socni-cli-install.log
echo "Starting SOCNI CLI installation at $(date)" > $LOG_FILE

# Check if binary exists, if not build it
if [ ! -f "$SOCNI_DIR/bin/socni-ctl" ]; then
  echo -e "${YELLOW}CLI binary not found. Building SOCNI CLI...${NC}"
  cd "$SOCNI_DIR"
  # Use cargo directly instead of make build
  cargo build --release
  mkdir -p bin
  cp ./target/release/socni-ctl bin/socni-ctl
  chmod +x bin/socni-ctl
  echo "Built SOCNI CLI binary" >> $LOG_FILE
fi

# Copy CLI binary
echo -e "${GREEN}Copying CLI binary...${NC}"
cp "$SOCNI_DIR/bin/socni-ctl" "/usr/local/bin/"
chmod +x "/usr/local/bin/socni-ctl"
echo "Copied CLI binary to /usr/local/bin" >> $LOG_FILE

# Run the CLI installation script if it exists
if [ -f "$SCRIPT_DIR/install-ctl.sh" ]; then
  echo -e "${GREEN}Running CLI installation script...${NC}"
  bash "$SCRIPT_DIR/install-ctl.sh"
  echo "Ran CLI installation script" >> $LOG_FILE
fi

echo -e "${GREEN}SOCNI CLI installation complete!${NC}"
echo "Installation completed at $(date)" >> $LOG_FILE

# Final message
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}SOCNI CLI installation completed successfully!${NC}"
echo -e "${GREEN}===============================================${NC}"
echo ""
echo -e "${YELLOW}Verify installation with:${NC}"
echo -e "${BLUE}socni-ctl --help${NC}"
echo ""
echo -e "${YELLOW}Note: The VLAN CNI plugin is not installed by this script.${NC}"
echo -e "${YELLOW}To install the CNI plugin, use the install-cni.sh script.${NC}"
echo "" 