#!/bin/bash
set -e

# Installation script for VLAN CNI plugin

# Default paths
CNI_BIN_DIR=${CNI_BIN_DIR:-/opt/cni/bin}
CNI_CONF_DIR=${CNI_CONF_DIR:-/etc/cni/net.d}
VLAN_CNI_STATE_DIR=${VLAN_CNI_STATE_DIR:-/var/lib/vlan-cni}

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${NC}"
  exit 1
fi

# Create log file
LOG_FILE=/var/log/vlan-cni-install.log
echo "Starting VLAN CNI plugin installation at $(date)" > $LOG_FILE

# Create directories
echo -e "${GREEN}Creating directories...${NC}"
mkdir -p $CNI_BIN_DIR
mkdir -p $CNI_CONF_DIR
mkdir -p $VLAN_CNI_STATE_DIR

# Copy binary
BINARY_PATH=$(dirname $0)/../target/release/vlan-cni
if [ ! -f "$BINARY_PATH" ]; then
  echo -e "${RED}Binary not found at $BINARY_PATH${NC}"
  echo -e "${YELLOW}Building binary...${NC}"
  
  # Navigate to project root and build
  cd $(dirname $0)/..
  cargo build --release >> $LOG_FILE 2>&1
  BINARY_PATH=./target/release/vlan-cni
fi

echo -e "${GREEN}Installing VLAN CNI plugin to $CNI_BIN_DIR...${NC}"
cp $BINARY_PATH $CNI_BIN_DIR/vlan
chmod +x $CNI_BIN_DIR/vlan
echo "Installed VLAN CNI binary to $CNI_BIN_DIR/vlan" >> $LOG_FILE

# Create default configuration if it doesn't exist
DEFAULT_CONF_PATH=$CNI_CONF_DIR/10-vlan.conflist
if [ ! -f "$DEFAULT_CONF_PATH" ]; then
  echo -e "${GREEN}Creating default configuration...${NC}"
  cat > $DEFAULT_CONF_PATH << EOF
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
  echo "Created default configuration at $DEFAULT_CONF_PATH" >> $LOG_FILE
fi

# Set up host VLAN interfaces if needed
echo -e "${GREEN}Setting up host VLAN interfaces...${NC}"
MASTER_INTERFACE=$(jq -r '.plugins[0].master' $DEFAULT_CONF_PATH 2>/dev/null || echo "eth0")
VLAN_ID=$(jq -r '.plugins[0].vlan' $DEFAULT_CONF_PATH 2>/dev/null || echo "100")
VLAN_INTERFACE="${MASTER_INTERFACE}.${VLAN_ID}"

# Check if master interface exists
if ip link show dev $MASTER_INTERFACE &>/dev/null; then
  # Check if VLAN interface already exists
  if ! ip link show dev $VLAN_INTERFACE &>/dev/null; then
    echo -e "${GREEN}Creating VLAN interface $VLAN_INTERFACE...${NC}"
    ip link add link $MASTER_INTERFACE name $VLAN_INTERFACE type vlan id $VLAN_ID
    ip link set dev $VLAN_INTERFACE up
    echo "Created VLAN interface $VLAN_INTERFACE" >> $LOG_FILE
  else
    echo -e "${YELLOW}VLAN interface $VLAN_INTERFACE already exists${NC}"
  fi
else
  echo -e "${RED}Master interface $MASTER_INTERFACE does not exist${NC}"
  echo "WARNING: Master interface $MASTER_INTERFACE does not exist" >> $LOG_FILE
fi

# Label the node if running in Kubernetes
if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
  echo -e "${GREEN}Running in Kubernetes, labeling node...${NC}"
  NODE_NAME=$(hostname)
  kubectl label node $NODE_NAME --overwrite vlan.cni.kubernetes.io/enabled=true
  kubectl label node $NODE_NAME --overwrite vlan.cni.kubernetes.io/vlan-$VLAN_ID=true
  echo "Labeled node $NODE_NAME with VLAN capability" >> $LOG_FILE
fi

echo -e "${GREEN}VLAN CNI plugin installation complete!${NC}"
echo "Installation completed at $(date)" >> $LOG_FILE