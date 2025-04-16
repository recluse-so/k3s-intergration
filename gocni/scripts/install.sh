#!/bin/bash
set -e

# VLAN CNI Plugin Installation Script
# This script installs the VLAN CNI plugin on a Kubernetes node

# Configuration
CNI_BIN_DIR=${CNI_BIN_DIR:-"/opt/cni/bin"}
CNI_CONF_DIR=${CNI_CONF_DIR:-"/etc/cni/net.d"}
VLAN_CNI_CONFIG_DIR=${VLAN_CNI_CONFIG_DIR:-"/etc/vlan-cni/config"}
VLAN_CNI_RUN_DIR=${VLAN_CNI_RUN_DIR:-"/var/run/vlan-cni"}
LOG_FILE=${LOG_FILE:-"/var/log/vlan-cni-install.log"}

# Ensure we're running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Create log file
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

log "Starting VLAN CNI plugin installation"

# Create required directories
log "Creating required directories"
mkdir -p $CNI_BIN_DIR $CNI_CONF_DIR $VLAN_CNI_CONFIG_DIR $VLAN_CNI_RUN_DIR

# Copy binary to CNI bin directory if running outside container
if [[ -f ./bin/vlan-cni ]]; then
    log "Copying binary from local build"
    cp ./bin/vlan-cni $CNI_BIN_DIR/
    chmod 755 $CNI_BIN_DIR/vlan-cni
# If running inside container, binary should already be at /opt/cni/bin
elif [[ ! -f $CNI_BIN_DIR/vlan-cni ]]; then
    log "ERROR: VLAN CNI binary not found!"
    exit 1
fi

# Verify binary
log "Verifying VLAN CNI binary"
if [[ ! -x $CNI_BIN_DIR/vlan-cni ]]; then
    log "ERROR: VLAN CNI binary is not executable!"
    chmod +x $CNI_BIN_DIR/vlan-cni
    log "Fixed permissions on VLAN CNI binary"
fi

# Configure CNI
log "Configuring VLAN CNI plugin"

# If running in Kubernetes with ConfigMap
if [[ -f $VLAN_CNI_CONFIG_DIR/vlan-cni.conf ]]; then
    log "Using configuration from ConfigMap"
    cp $VLAN_CNI_CONFIG_DIR/vlan-cni.conf $CNI_CONF_DIR/10-vlan.conflist
# Otherwise, create a default configuration
else
    log "Creating default VLAN CNI configuration"
    cat > $CNI_CONF_DIR/10-vlan.conflist <<EOF
{
  "cniVersion": "0.3.1",
  "name": "vlan-network",
  "plugins": [
    {
      "type": "vlan-cni",
      "master": "eth0",
      "mappings": []
    }
  ]
}
EOF
fi

# Setup host networking (VLAN interfaces on the host)
setup_host_vlans() {
    log "Setting up host VLAN interfaces"
    
    # Check if config contains VLAN mappings
    if [[ -f $CNI_CONF_DIR/10-vlan.conflist ]]; then
        # Get interface name
        MASTER_IFACE=$(grep -o '"master":[[:space:]]*"[^"]*"' $CNI_CONF_DIR/10-vlan.conflist | cut -d'"' -f4)
        
        if [[ -z "$MASTER_IFACE" ]]; then
            log "WARNING: Master interface not specified in config, using default eth0"
            MASTER_IFACE="eth0"
        fi
        
        # Check if the master interface exists
        if ! ip link show $MASTER_IFACE &>/dev/null; then
            log "ERROR: Master interface $MASTER_IFACE not found on host!"
            # Try to find a suitable interface
            ALTERNATE_IFACE=$(ip -o link show | grep -v "lo" | head -n1 | awk -F': ' '{print $2}')
            if [[ -n "$ALTERNATE_IFACE" ]]; then
                log "Using alternate interface: $ALTERNATE_IFACE"
                MASTER_IFACE=$ALTERNATE_IFACE
                # Update config
                sed -i "s/\"master\":[[:space:]]*\"[^\"]*\"/\"master\": \"$MASTER_IFACE\"/" $CNI_CONF_DIR/10-vlan.conflist
            else
                log "ERROR: No suitable network interface found on host!"
                exit 1
            fi
        fi
        
        # Extract VLAN IDs from config
        VLAN_IDS=$(grep -o '"vlan":[[:space:]]*[0-9]*' $CNI_CONF_DIR/10-vlan.conflist | cut -d':' -f2 | tr -d ' ')
        
        # Create VLAN interfaces if not already present
        for VLAN_ID in $VLAN_IDS; do
            VLAN_IFACE="${MASTER_IFACE}.${VLAN_ID}"
            
            # Check if VLAN interface already exists
            if ! ip link show $VLAN_IFACE &>/dev/null; then
                log "Creating VLAN interface $VLAN_IFACE (VLAN ID: $VLAN_ID)"
                ip link add link $MASTER_IFACE name $VLAN_IFACE type vlan id $VLAN_ID
                ip link set $VLAN_IFACE up
                
                # Optional: Configure IP addressing on the VLAN interface
                # ip addr add 10.$VLAN_ID.0.1/24 dev $VLAN_IFACE
            else
                log "VLAN interface $VLAN_IFACE already exists"
                # Ensure it's up
                ip link set $VLAN_IFACE up
            fi
        done
    else
        log "WARNING: No VLAN configuration found"
    fi
}

# Setup host VLANs
setup_host_vlans

# Mark nodes with appropriate labels for VLAN support
if command -v kubectl &>/dev/null; then
    NODE_NAME=$(hostname)
    
    if [[ -n "$NODE_NAME" ]]; then
        log "Labeling node $NODE_NAME for VLAN support"
        
        # Extract VLAN IDs from config and set labels
        if [[ -f $CNI_CONF_DIR/10-vlan.conflist ]]; then
            VLAN_IDS=$(grep -o '"vlan":[[:space:]]*[0-9]*' $CNI_CONF_DIR/10-vlan.conflist | cut -d':' -f2 | tr -d ' ')
            
            for VLAN_ID in $VLAN_IDS; do
                kubectl label node $NODE_NAME networking/vlan$VLAN_ID=true --overwrite &>>$LOG_FILE || true
            done
        fi
    else
        log "WARNING: Could not determine node name, skipping node labeling"
    fi
else
    log "WARNING: kubectl not found, skipping node labeling"
fi

# Create a file to indicate successful installation
touch $VLAN_CNI_RUN_DIR/installed

log "VLAN CNI plugin installation completed successfully"

# If running in container, keep it alive for logging/debugging purposes
if [[ -f /.dockerenv ]]; then
    log "Running in container, starting monitoring loop"
    
    # Trap to ensure clean exit
    trap 'log "Received signal to terminate"; exit 0' SIGTERM SIGINT
    
    # Monitor loop
    while true; do
        sleep 30
        
        # Check if any VLANs need to be reconfigured
        if [[ -f $VLAN_CNI_CONFIG_DIR/vlan-cni.conf ]]; then
            if [[ $VLAN_CNI_CONFIG_DIR/vlan-cni.conf -nt $CNI_CONF_DIR/10-vlan.conflist ]]; then
                log "Configuration updated, reconfiguring..."
                cp $VLAN_CNI_CONFIG_DIR/vlan-cni.conf $CNI_CONF_DIR/10-vlan.conflist
                setup_host_vlans
            fi
        fi
    done
fi

exit 0