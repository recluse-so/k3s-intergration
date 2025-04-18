# SOCNI: Security-First VLAN CNI Plugin for Kubernetes

SOCNI is a Container Network Interface (CNI) plugin that creates and manages VLAN interfaces for Kubernetes pods with security as a primary focus. It leverages Aranya's robust security model for policy-based networking.

## Features

### Security-First Architecture

- **Built on Aranya Security**: Utilizes Aranya's cryptographic identity, policy enforcement, and secure synchronization for networking decisions
- **Policy-Based Networking**: Enforces fine-grained access control to network resources based on pod identity
- **Memory Safety**: Implemented in Rust to prevent common memory-related vulnerabilities
- **Distributed Consistency**: Uses Aranya's protocol for network configuration across nodes
- **Strong Encryption**: Leverages Aranya's cryptographic foundations for secure communication

## Prerequisites

### System Requirements

- Linux kernel 4.19 or later
- Kubernetes 1.18+
- Root privileges on nodes
- Network interface supporting VLAN operations
- System packages:
  - `iproute2`
  - `bridge-utils`
  - `vlan` kernel module
- Rust toolchain (for building from source)

### Aranya Requirements

- Aranya daemon v1.0.0 or later running on nodes
- Valid Aranya tenant configuration
- Network connectivity between nodes for policy synchronization

### Multus CNI

- Multus CNI v3.9.0 or later
- Required for managing multiple network interfaces in Kubernetes pods
- Enables SOCNI to work alongside other CNI plugins
- Provides the NetworkAttachmentDefinition CRD for VLAN configuration
- [Multus CNI GitHub Repository](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Multus CNI Documentation](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/quickstart.md)

## Installation

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/username/socni.git
cd socni

# Build the binaries
make build

# Install the CNI plugin and CLI tool
sudo make install
```

The installation process will:

1. Build the CNI plugin and CLI tool
2. Install the CNI plugin to `/opt/cni/bin/`
3. Install the CLI tool to `/usr/local/bin/`
4. Run the installation script to set up configuration

### Installing Only the CLI Tool

If you only need the command-line tool:

```bash
sudo make install-cli
```

### Docker Installation

You can also use the provided Docker image:

```bash
# Build the Docker image
make docker-build

# Run the container
docker run -v /opt/cni/bin:/opt/cni/bin -v /etc/cni/net.d:/etc/cni/net.d vlan-cni:latest /install.sh
```

### Kubernetes Deployment

To deploy SOCNI to a Kubernetes cluster:

```bash
# Deploy the DaemonSet
make deploy

# Create network attachment definitions
make create-networks
```

### Upgrading

To upgrade an existing installation:

```bash
# Build the latest version
make build

# Install the updated binaries
sudo make install
```

## Configuration

### Basic Configuration

Create a `socni.conflist` in your CNI configuration directory (typically `/etc/cni/net.d/`):

```json
{
  "cniVersion": "1.0.0",
  "name": "socni-network",
  "plugins": [
    {
      "type": "vlan",
      "master": "eth0",
      "vlan": 100,
      "mtu": 1500,
      "ipam": {
        "type": "host-local",
        "subnet": "10.100.0.0/24",
        "gateway": "10.100.0.1"
      }
    }
  ]
}
```

### Configuration Parameters

| Parameter | Required | Description | Default |
|-----------|----------|-------------|---------|
| master | Yes | Master interface for VLAN | - |
| vlan | Yes | VLAN ID (1-4094) | - |
| mtu | No | Interface MTU | 1500 |
| ipam | No | IPAM configuration | - |

### Advanced Configuration

#### Multi-VLAN Configuration

```json
{
  "cniVersion": "1.0.0",
  "name": "multi-vlan-network",
  "plugins": [
    {
      "type": "vlan",
      "master": "eth0",
      "vlan": 100,
      "ipam": {
        "type": "host-local",
        "subnet": "10.100.0.0/24"
      }
    },
    {
      "type": "vlan",
      "master": "eth1",
      "vlan": 200,
      "ipam": {
        "type": "host-local",
        "subnet": "10.200.0.0/24"
      }
    }
  ]
}
```

### Aranya Security Integration

#### Environment Variables

```
ARANYA_SOCKET_PATH=/var/run/aranya/api.sock
ARANYA_TENANT_ID=<tenant-id>
ARANYA_LOG_LEVEL=info
```

#### Pod Annotations

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  annotations:
    socni.network.aranya.io/tenant-id: "finance"
    socni.network.aranya.io/vlan: "100"
    socni.network.aranya.io/security-level: "high"
spec:
  # ...
```

## Security Features

### Fine-Grained Access Control
SOCNI integrates with Aranya's label-based access control, allowing you to define which pods can access specific VLANs.

### Runtime Access Verification
The CNI plugin performs access checks at:

- Creation time (add)
- Validation time (check)
- Usage time (runtime)

### Network Isolation
SOCNI ensures complete network isolation between different tenants unless explicitly allowed.

### Audit Logging
All network access attempts are logged in Aranya for auditability and compliance.

### Security Best Practices

1. **Key Management**:
   - Rotate Aranya keys every 90 days
   - Use separate keys for different environments
   - Store keys in a secure key management system

2. **Multi-tenant Security**:
   - Use separate VLANs for different tenants
   - Implement strict network policies
   - Regular security audits
   - Monitor access patterns

3. **Network Security**:
   - Enable MAC address filtering
   - Implement rate limiting
   - Use encrypted communication channels
   - Regular security updates

## Management Tools

### socni-ctl

The `socni-ctl` command-line tool allows you to manage VLANs and access control:

```bash
# Install the tool
sudo make install-cli

# Basic commands
socni-ctl create --id 100 --master eth0  # Create a VLAN
socni-ctl list                           # List available VLANs
socni-ctl grant --vlan-id 100 --target-tenant finance  # Grant access
socni-ctl revoke --vlan-id 100 --target-tenant finance # Revoke access
socni-ctl status --id 100                # Check VLAN status
```

## Troubleshooting

### Common Issues

1. **Access Denied Errors**:

   ```
   "Access denied by Aranya policy engine: No permission to use VLAN 100"
   ```

   Solution: 
   - Verify tenant ID configuration
   - Check VLAN access permissions
   - Ensure Aranya daemon is running
   - Check policy configuration

2. **Aranya Connection Issues**:

   ```
   "Failed to connect to Aranya daemon at /var/run/aranya/api.sock"
   ```

   Solution:
   - Verify Aranya daemon status: `systemctl status aranya`
   - Check socket permissions
   - Verify network connectivity
   - Check Aranya logs

3. **Network Namespace Issues**:

   ```
   "Failed to open network namespace file"
   ```

   Solution:
   - Verify pod namespace exists
   - Check namespace permissions
   - Ensure CNI plugin has root access
   - Verify kernel namespace support

4. **Performance Issues**:

   ```
   "Slow network performance or high latency"
   ```

   Solution:
   - Check network interface statistics
   - Verify VLAN configuration
   - Monitor system resources
   - Check for network congestion

### Diagnostic Commands

```bash
# Check CNI plugin status
socni-ctl status

# Verify Aranya connectivity
socni-ctl check-aranya

# Test network connectivity
socni-ctl test-network --vlan-id 100

# View detailed logs
journalctl -t socni-cni -f

# Check system resources
socni-ctl diagnostics
```

## Architecture

SOCNI consists of several components working together to provide secure network isolation:

1. **VLAN CNI Plugin**
   - Core network plugin implementing VLAN functionality
   - Handles pod network interface creation and configuration
   - Manages VLAN tagging and network isolation

2. **Multus CNI Integration**
   - Acts as a meta-plugin to manage multiple network interfaces
   - Allows pods to have both primary and secondary networks
   - Enables SOCNI to work alongside other CNI plugins
   - Provides NetworkAttachmentDefinition CRD for VLAN configuration
   - Handles network interface attachment and detachment

3. **SOCNI-CTL Tool**
   - Command-line interface for management
   - Handles configuration and monitoring
   - Provides troubleshooting capabilities

4. **Kubernetes Integration**
   - DaemonSet for deploying the CNI plugin
   - NetworkAttachmentDefinition for VLAN configuration
   - Integration with Kubernetes networking

The architecture follows this flow:
1. Multus CNI manages the primary network interface
2. SOCNI plugin handles VLAN configuration and isolation
3. NetworkAttachmentDefinition defines VLAN parameters
4. Pods can request VLAN networks through annotations

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details. 
