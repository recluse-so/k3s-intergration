#!/bin/bash
# File: socni/scripts/test_with_aranya.sh

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}This script must be run as root to create network namespaces${NC}"
  exit 1
fi

# Clean up function
cleanup() {
  echo -e "${YELLOW}Cleaning up...${NC}"
  ip netns del test_vlan_netns 2>/dev/null || true
  ip link del test_vlan 2>/dev/null || true
}

# Set up trap to clean up on exit
trap cleanup EXIT

echo -e "${GREEN}Setting up test environment...${NC}"

# Create test network namespace
ip netns add test_vlan_netns || true
echo "Created test network namespace"

# Build the plugin
echo -e "${YELLOW}Building VLAN CNI plugin...${NC}"
cd "$(dirname "$0")/.." && cargo build

# Run the tests
echo -e "${GREEN}Running integration tests with Aranya policies...${NC}"
cd "$(dirname "$0")/.." && RUST_TEST_THREADS=1 cargo test integration_test -- --nocapture --ignored

echo -e "${GREEN}Tests completed.${NC}"