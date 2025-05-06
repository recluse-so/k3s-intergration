#!/bin/bash

# Exit on error
set -e

# Configuration
ARANYA_DIR="/var/lib/aranya"
ARANYA_RUN="/var/run/aranya"
ARANYA_CONFIG="$ARANYA_DIR/config.json"
ARANYA_KEYSTORE="$ARANYA_DIR/keystore"
ARANYA_BINARY="/Users/asaunders/githubRepos/k3s-intergration/aranya/target/release/aranya-daemon"
ARANYA_PORT="4322"

# Check if port is in use
if lsof -i :$ARANYA_PORT > /dev/null 2>&1; then
    echo "Port $ARANYA_PORT is already in use. Please choose a different port or stop the process using it."
    exit 1
fi

# Create directories
echo "Creating Aranya directories..."
sudo mkdir -p "$ARANYA_DIR"
sudo mkdir -p "$ARANYA_RUN"
sudo mkdir -p "$ARANYA_KEYSTORE"
sudo chmod 700 "$ARANYA_DIR"
sudo chmod 700 "$ARANYA_KEYSTORE"

# Create config file
echo "Creating Aranya configuration..."
sudo tee "$ARANYA_CONFIG" > /dev/null << EOF
{
    "name": "aranya-test",
    "work_dir": "/var/lib/aranya",
    "uds_api_path": "/var/run/aranya/api.sock",
    "pid_file": "/var/run/aranya/daemon.pid",
    "sync_addr": "0.0.0.0:$ARANYA_PORT",
    "afc": {
        "shm_path": "/afc",
        "unlink_on_startup": true,
        "unlink_at_exit": true,
        "create": true,
        "max_chans": 100
    }
}
EOF

# Set permissions
sudo chmod 600 "$ARANYA_CONFIG"

echo "Aranya setup complete. You can now start the daemon with:"
echo "sudo $ARANYA_BINARY $ARANYA_CONFIG" 