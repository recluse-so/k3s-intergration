# SOCNI: Secure VLAN CNI Plugin Command Line Tool

`socni-ctl` is a command line tool for managing VLAN networks in Kubernetes environments with Aranya security integration. It provides a simple interface for creating, listing, and managing VLANs with strong tenant isolation.

## Installation

```bash
# Build and install from source
cd socni
make build
sudo make install-cli

# Or install directly if you have the binary
sudo cp socni-ctl /usr/local/bin/
sudo chmod +x /usr/local/bin/socni-ctl
```

## Global Options

These options apply to all commands:

| Option | Description | Default |
|--------|-------------|---------|
| `--socket PATH` | Path to Aranya daemon socket | `/var/run/aranya/api.sock` |
| `--tenant-id ID` | Tenant ID to use for operations | `default` |
| `--config-dir PATH` | Path to config directory | `/etc/cni/net.d` |
| `-v, --verbose` | Enable verbose output | Disabled |
| `--help` | Show help information | |

## Commands

### Create VLAN

Creates a new VLAN with tenant isolation.

```bash
socni-ctl create --id VLAN_ID [--master INTERFACE] [--mtu MTU] [--label KEY=VALUE]
```

| Option | Description |
|--------|-------------|
| `--id` | VLAN ID (1-4094, required) |
| `--master` | Master interface (optional, defaults to system default) |
| `--mtu` | MTU for the VLAN interface (optional) |
| `--label` | Security labels (can be specified multiple times) |

Examples:

```bash
# Create VLAN 100 with default settings
socni-ctl create --id 100

# Create VLAN with custom master and MTU
socni-ctl create --id 200 --master eth1 --mtu 9000

# Create VLAN with security labels
socni-ctl create --id 300 --label security=high --label environment=production
```

### List VLANs

Lists available VLANs accessible by the current tenant.

```bash
socni-ctl list [--detailed]
```

| Option | Description |
|--------|-------------|
| `--detailed` | Show detailed information including tenants and labels |

Examples:

```bash
# List all accessible VLANs
socni-ctl list

# List with detailed information
socni-ctl list --detailed
```

### Grant VLAN Access

Grant another tenant access to a VLAN. Requires admin privileges.

```bash
socni-ctl grant --vlan-id VLAN_ID --target-tenant TENANT_ID
```

| Option | Description |
|--------|-------------|
| `--vlan-id` | VLAN ID to grant access to (required) |
| `--target-tenant` | Target tenant ID to grant access to (required) |

Example:

```bash
# Grant access to VLAN 100 to tenant 'finance'
socni-ctl --tenant-id admin grant --vlan-id 100 --target-tenant finance
```

### Revoke VLAN Access

Revoke tenant access to a VLAN. Requires admin privileges.

```bash
socni-ctl revoke --vlan-id VLAN_ID --target-tenant TENANT_ID
```

| Option | Description |
|--------|-------------|
| `--vlan-id` | VLAN ID to revoke access from (required) |
| `--target-tenant` | Target tenant ID to revoke access from (required) |

Example:

```bash
# Revoke access to VLAN 100 from tenant 'finance'
socni-ctl --tenant-id admin revoke --vlan-id 100 --target-tenant finance
```

### Generate VLAN Configuration

Generate a network configuration file for the VLAN CNI plugin.

```bash
socni-ctl generate --id VLAN_ID --master INTERFACE [--mtu MTU] [--name NAME] [--output PATH] [--subnet CIDR] [--gateway IP]
```

| Option | Description |
|--------|-------------|
| `--id` | VLAN ID (1-4094, required) |
| `--master` | Master interface (required) |
| `--mtu` | MTU for the VLAN interface (optional) |
| `--name` | Network name (optional, defaults to "vlan-network") |
| `--output` | Output file path (optional, prints to stdout if not specified) |
| `--subnet` | IPAM subnet in CIDR notation (optional) |
| `--gateway` | IPAM gateway IP (optional) |

Examples:

```bash
# Generate basic configuration and print to stdout
socni-ctl generate --id 100 --master eth0

# Generate with IPAM configuration and write to file
socni-ctl generate --id 200 --master eth0 --subnet 10.200.0.0/24 --gateway 10.200.0.1 --output /etc/cni/net.d/200-vlan.conflist

# Generate with custom name and MTU
socni-ctl generate --id 300 --master eth0 --name finance-vlan --mtu 1500 --output /tmp/finance-vlan.json
```

### Install CNI Plugin

Install the VLAN CNI plugin to the system.

```bash
socni-ctl install [--yes] [--bin-dir PATH]
```

| Option | Description |
|--------|-------------|
| `--yes` | Skip confirmation prompts |
| `--bin-dir` | Installation directory (defaults to `/opt/cni/bin`) |

Example:

```bash
# Install with confirmation
socni-ctl install

# Install without confirmation to custom directory
socni-ctl install --yes --bin-dir /usr/local/cni/bin
```

### Check VLAN Status

Check the status of VLAN interfaces on the host.

```bash
socni-ctl status [--id VLAN_ID]
```

| Option | Description |
|--------|-------------|
| `--id` | Specific VLAN ID to check (optional, checks all VLANs if not specified) |

Examples:

```bash
# Check all VLAN interfaces
socni-ctl status

# Check specific VLAN
socni-ctl status --id 100
```

## Using with Aranya for Multi-Tenant Environments

When using `socni-ctl` with Aranya for multi-tenant environments, always specify the tenant ID:

```bash
# As admin tenant
socni-ctl --tenant-id admin list --detailed

# As specific tenant
socni-ctl --tenant-id finance create --id 100 --label department=finance

# Granting cross-tenant access (admin only)
socni-ctl --tenant-id admin grant --vlan-id 100 --target-tenant hr
```

## Examples for Common Tasks

### Setting Up a New VLAN for a Tenant

```bash
# Create VLAN 100 for finance tenant
socni-ctl --tenant-id admin create --id 100 --master eth0 --label department=finance

# Generate network configuration
socni-ctl generate --id 100 --master eth0 --subnet 10.100.0.0/24 --output /etc/cni/net.d/finance-vlan.conflist

# Grant access to finance tenant
socni-ctl --tenant-id admin grant --vlan-id 100 --target-tenant finance
```

### Creating a Shared VLAN

```bash
# Create shared VLAN 999
socni-ctl --tenant-id admin create --id 999 --master eth0 --label purpose=shared-services

# Grant access to multiple tenants
socni-ctl --tenant-id admin grant --vlan-id 999 --target-tenant finance
socni-ctl --tenant-id admin grant --vlan-id 999 --target-tenant hr
socni-ctl --tenant-id admin grant --vlan-id 999 --target-tenant engineering
```

### Checking VLAN Configuration

```bash
# List all VLANs with details
socni-ctl --tenant-id admin list --detailed

# Check VLAN interfaces
socni-ctl status

# Check specific VLAN
socni-ctl status --id 100
```

## Troubleshooting

If you encounter issues:

1. Use the `--verbose` flag for more detailed output:

   ```bash
   socni-ctl --verbose list
   ```

2. Check if the Aranya daemon is running:

   ```bash
   ls -la /var/run/aranya/api.sock
   ```

3. Verify permissions - most operations require root/sudo:

   ```bash
   sudo socni-ctl status
   ```

4. For installation issues, run with specific paths:

   ```bash
   sudo socni-ctl install --bin-dir /opt/cni/bin
   ```

## Notes

- Most commands that interact with network interfaces require root privileges
- Admin operations (grant, revoke) require the admin tenant ID
- The tool assumes Aranya daemon is running and accessible at the specified socket path
