#!/bin/bash

# Exit on error
set -e

# Configuration
ARANYA_DIR="/var/lib/aranya"
ARANYA_RUN="/var/run/aranya"
ARANYA_CONFIG="$ARANYA_DIR/config.json"
ARANYA_BINARY="/Users/asaunders/githubRepos/k3s-intergration/aranya/target/release/aranya-daemon"
ARANYA_PORT="4322"
TEST_DIR="/Users/asaunders/githubRepos/k3s-intergration/socni/tests"

# Function to cleanup
cleanup() {
    echo "Cleaning up..."
    # Kill any running Aranya daemon
    sudo pkill aranya-daemon || true
    # Remove Aranya directories
    sudo rm -rf "$ARANYA_DIR" "$ARANYA_RUN"
}

# Trap cleanup on script exit
trap cleanup EXIT

# Create directories and setup Aranya
echo "Setting up Aranya environment..."
sudo mkdir -p "$ARANYA_DIR"
sudo mkdir -p "$ARANYA_RUN"
sudo chmod 700 "$ARANYA_DIR"

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

sudo chmod 600 "$ARANYA_CONFIG"

# Start Aranya daemon
echo "Starting Aranya daemon..."
sudo "$ARANYA_BINARY" "$ARANYA_CONFIG" &
ARANYA_PID=$!

# Wait for daemon to start
sleep 5

# Run tests
echo "Running tests..."
cd "$TEST_DIR"
cargo test -- --nocapture

# The cleanup function will be called automatically on exit 