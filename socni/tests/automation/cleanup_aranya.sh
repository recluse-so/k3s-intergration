#!/bin/bash

# Exit on error
set -e

# Configuration
ARANYA_DIR="/var/lib/aranya"
ARANYA_RUN="/var/run/aranya"
ARANYA_SHM="/afc"

# Stop Aranya daemon if running
if [ -f "/var/run/aranya/daemon.pid" ]; then
    echo "Stopping Aranya daemon..."
    sudo kill $(cat /var/run/aranya/daemon.pid) 2>/dev/null || true
fi

# Remove directories and files
echo "Cleaning up Aranya files..."
sudo rm -rf "$ARANYA_DIR"
sudo rm -rf "$ARANYA_RUN"
sudo rm -rf "$ARANYA_SHM"

echo "Aranya cleanup complete" 