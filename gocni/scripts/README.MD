# Key Functions of the Script

## Environment Setup

Sets configuration directories with defaults that can be overridden
Ensures the script runs as root
Creates log files for tracking installation progress

## Binary Installation

Copies the VLAN CNI binary to the CNI plugins directory (/opt/cni/bin/)
Handles both standalone installation and container-based installation scenarios
Verifies executable permissions

## Configuration Creation

Copies configuration from ConfigMap if running in Kubernetes
Creates a default configuration if none exists
Places configuration in the CNI configuration directory (/etc/cni/net.d/)

## Host VLAN Setup

Parses the configuration to extract VLAN IDs and master interface
Creates VLAN interfaces on the host if they don't exist
Sets the VLAN interfaces to the "up" state

## Node Labeling (when running in Kubernetes)

Labels the node with appropriate VLAN capability tags
These labels are used by pod selectors to ensure pods land on nodes with the right VLAN support

## Container Operation Mode

When running as a container in the DaemonSet, keeps the container alive
Monitors for configuration changes and reconfigures VLANs when needed

This script serves both the local development workflow (when run manually) and the production deployment (when run inside the container). It ensures that all the necessary pieces are in place for the VLAN CNI plugin to work correctly, setting up both the CNI plugin itself and the required host network configuration.