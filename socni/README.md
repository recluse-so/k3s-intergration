# SOCNI: Security-First VLAN CNI Plugin for Kubernetes

SOCNI is a Container Network Interface (CNI) plugin that creates and manages VLAN interfaces for Kubernetes pods with security as a primary focus. It leverages Aranya's robust security model for policy-based networking.

## Features

### Security-First Architecture
- **Built on Aranya Security**: Utilizes Aranya's cryptographic identity, policy enforcement, and secure synchronization for networking decisions
- **Policy-Based Networking**: Enforces fine-grained access control to network resources based on pod identity
- **Memory Safety**: Implemented in Rust to prevent common memory-related vulnerabilities
- **Distributed Consistency**: Uses Aranya's protocol for network configuration across nodes
- **Strong Encryption**: Leverages Aranya's cryptographic foundations for secure communication

## Installation

### Prerequisites
- Kubernetes 1.18+
- Aranya daemon running on nodes (for policy enforcement)
- Linux with VLAN kernel module loaded
- Root privileges on nodes

### Using Helm
```bash
helm repo add socni https://socni.github.io/charts
helm install socni socni/socni-cni --set aranya.enabled=true
```

### Manual Installation
```bash
git clone https://github.com/username/socni.git
cd socni
make build
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

### Aranya Security Integration

Set the following environment variables for the CNI plugin:

```
ARANYA_SOCKET_PATH=/var/run/aranya/api.sock
ARANYA_TENANT_ID=<tenant-id>
```

Or use annotations in your pod template:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  annotations:
    socni.network.aranya.io/tenant-id: "finance"
    socni.network.aranya.io/vlan: "100"
spec:
  # ...
```

## Using Policy-Based Networking

### 1. Create VLAN with Security Policies

Use the `socni-ctl` command line tool to create VLANs with security policies:

```bash
# Create VLAN with specific tenant access
socni-ctl --tenant-id admin create --id 100 --master eth0 --label team=finance

# Grant access to specific tenants
socni-ctl --tenant-id admin grant --vlan-id 100 --target-tenant finance
```

### 2. Configure Kubernetes with Network Policies

Create a network policy that matches your Aranya policies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-finance-vlan
spec:
  podSelector:
    matchLabels:
      team: finance
  ingress:
  - from:
    - podSelector:
        matchLabels:
          team: finance
```

### 3. Verify Access Control

```bash
# Check if a pod has access to a VLAN
socni-ctl --tenant-id finance status --id 100

# List all VLANs accessible by a tenant
socni-ctl --tenant-id finance list
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
   Solution: Grant access using `socni-ctl grant` or check your tenant ID configuration.

2. **Aranya Connection Issues**:
   ```
   "Failed to connect to Aranya daemon at /var/run/aranya/api.sock"
   ```
   Solution: Ensure Aranya daemon is running and the socket path is correct.

3. **Network Namespace Issues**:
   ```
   "Failed to open network namespace file"
   ```
   Solution: Ensure the pod's network namespace is correctly created.

### Logs

SOCNI logs to the host system journal with the tag `socni-cni`:

```bash
journalctl -t socni-cni -f
```

## Architecture

SOCNI consists of:

1. **CNI Plugin**: The VLAN network plugin that integrates with Kubernetes
2. **Aranya Client**: Integration with Aranya's policy engine for access control
3. **Command-Line Tools**: Tools for VLAN management and policy configuration

The security architecture ensures:
- Network isolation between pods and VLANs
- Fine-grained access control based on identity
- Cryptographic verification of access rights
- Consistent network configuration across nodes

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details. 