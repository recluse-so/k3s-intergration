#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default installation path
INSTALL_DIR=${INSTALL_DIR:-/usr/local/bin}

# Log file
LOG_FILE=/var/log/socni-ctl-install.log

# Ensure running as root if installing to a system directory
if [[ "$INSTALL_DIR" == "/usr/local/bin" || "$INSTALL_DIR" == "/usr/bin" ]] && [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Installing to $INSTALL_DIR requires root privileges.${NC}"
  echo -e "${YELLOW}Please run as root or specify a different INSTALL_DIR.${NC}"
  exit 1
fi

# Display banner
echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}         SOCNI-CTL Command Line Tool Installer        ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

echo "Starting socni-ctl installation at $(date)" > "$LOG_FILE"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}Rust not found. Installing Rust...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >> "$LOG_FILE" 2>&1
    source "$HOME/.cargo/env"
    echo -e "${GREEN}Rust installed${NC}"
else
    echo -e "${GREEN}Rust found${NC}"
fi

# Create installation directory if it doesn't exist
mkdir -p "$INSTALL_DIR"
echo "Created directory: $INSTALL_DIR" >> "$LOG_FILE"

# Build and install socni-ctl
echo -e "${YELLOW}Building socni-ctl...${NC}"
cd "$(dirname "$0")/.." || exit 1

# Check if we're in the socni directory
if [ ! -f "Cargo.toml" ]; then
    echo -e "${RED}Not in the socni directory. Please run this script from socni/scripts${NC}"
    exit 1
fi

# Build the project
echo -e "${YELLOW}Building socni-ctl...${NC}"
cargo build --release --bin socni-ctl >> "$LOG_FILE" 2>&1
echo -e "${GREEN}Build completed successfully${NC}"

# Install socni-ctl
echo -e "${YELLOW}Installing socni-ctl to $INSTALL_DIR...${NC}"
cp "target/release/socni-ctl" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/socni-ctl"
echo "Installed socni-ctl to $INSTALL_DIR" >> "$LOG_FILE"

# Check if the installation directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "${YELLOW}Warning: $INSTALL_DIR is not in your PATH.${NC}"
    
    # Suggest adding to PATH if the user is not root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}You may want to add it to your PATH:${NC}"
        echo -e "${BLUE}  export PATH=\$PATH:$INSTALL_DIR${NC}"
        echo -e "${YELLOW}Add this to your .bashrc or .zshrc to make it permanent.${NC}"
    fi
else
    echo -e "${GREEN}$INSTALL_DIR is in your PATH. You can run socni-ctl directly.${NC}"
fi

# Create a simple tutorial
echo -e "${YELLOW}Creating socni-ctl tutorial...${NC}"
TUTORIAL_DIR="$HOME/socni-tutorials"
mkdir -p "$TUTORIAL_DIR"

cat > "$TUTORIAL_DIR/socni-ctl-tutorial.md" << EOF
# SOCNI-CTL Tutorial

## Basic Commands

List available VLANs:
\`\`\`
socni-ctl list
\`\`\`

Get detailed VLAN information:
\`\`\`
socni-ctl list --detailed
\`\`\`

Create a new VLAN:
\`\`\`
socni-ctl create --id 200 --master eth0 --label security=high
\`\`\`

Check VLAN interface status:
\`\`\`
socni-ctl status
socni-ctl status --id 100
\`\`\`

## Using with Aranya

When using with Aranya, specify your tenant ID:
\`\`\`
socni-ctl --tenant-id your-tenant-id list
\`\`\`

Grant access to a VLAN to another tenant:
\`\`\`
socni-ctl --tenant-id admin-tenant grant --vlan-id 100 --target-tenant other-tenant
\`\`\`

## Generate Configuration Files

Generate a new network configuration:
\`\`\`
socni-ctl generate --id 300 --master eth0 --subnet 10.30.0.0/24 --output /tmp/vlan300.conf
\`\`\`

## Other Commands

For a complete list of commands:
\`\`\`
socni-ctl --help
\`\`\`

For help with a specific command:
\`\`\`
socni-ctl <command> --help
\`\`\`
EOF

echo -e "${GREEN}Created tutorial at $TUTORIAL_DIR/socni-ctl-tutorial.md${NC}"

# Final message
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}socni-ctl installation completed successfully!${NC}"
echo -e "${GREEN}===============================================${NC}"
echo ""
echo -e "${YELLOW}Verify installation with:${NC}"
echo -e "${BLUE}socni-ctl --help${NC}"
echo ""
echo -e "${YELLOW}See the tutorial at:${NC}"
echo -e "${BLUE}$TUTORIAL_DIR/socni-ctl-tutorial.md${NC}"
echo ""
echo -e "${YELLOW}Note: This installation only includes the command line tool.${NC}"
echo -e "${YELLOW}The VLAN CNI plugin is not installed by this script.${NC}"
echo ""
echo "Installation completed at $(date)" >> "$LOG_FILE"