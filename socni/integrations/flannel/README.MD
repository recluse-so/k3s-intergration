# Integrating SOCNI with Flannel in a K3s Environment

You're right - K3s uses Flannel as its default Container Network Interface (CNI) plugin. This presents a specific integration scenario for your SOCNI implementation. Here's how SOCNI works with Flannel in a K3s environment:

## Flannel and SOCNI Coexistence 

### How Flannel Works in K3s

Flannel in K3s:
1. Creates an overlay network (typically VXLAN-based)
2. Assigns pods to a flat network (10.42.0.0/16 by default)
3. Handles pod-to-pod routing across nodes
4. Uses the primary network interface for encapsulation

### How SOCNI Integrates with Flannel

The good news is that SOCNI is designed to work as a **secondary network plugin** alongside primary CNIs like Flannel:

```
                  ┌───────────────┐
                  │      Pod      │
                  │               │
┌─────────────────┼───────────────┼─────────────────┐
│                 │               │                 │
│  ┌─────────┐    │    ┌─────────┐│                 │
│  │  eth0   │────┼────│ Flannel ││                 │
│  └─────────┘    │    └─────────┘│                 │
│                 │               │                 │
│  ┌─────────┐    │    ┌─────────┐│                 │
│  │  net1   │────┼────│  SOCNI  ││                 │
│  └─────────┘    │    └─────────┘│                 │
│                 │               │                 │
└─────────────────┴───────────────┴─────────────────┘
```

1. **Flannel manages `eth0`** - The primary network interface remains under Flannel's control
2. **SOCNI adds `net1`** - SOCNI adds a secondary VLAN interface for isolated network access
3. **Distinct traffic paths** - Regular cluster traffic uses Flannel, VLAN traffic uses SOCNI

## Implementation Steps for K3s with Flannel

Here's how to implement SOCNI alongside Flannel in a K3s environment:

### 1. Install Multus CNI as a Meta-Plugin

Multus allows multiple CNI plugins to coexist:

```bash
# Create multus installation directory
mkdir -p multus-install
cd multus-install

# Download the Multus installer
curl -L -o multus-daemonset.yml https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml

# Modify for K3s (if using a non-default CNI directory)
sed -i 's|/etc/cni/net.d|/var/lib/rancher/k3s/agent/etc/cni/net.d|g' multus-daemonset.yml
sed -i 's|/opt/cni/bin|/var/lib/rancher/k3s/data/current/bin|g' multus-daemonset.yml

# Apply the multus manifest
kubectl apply -f multus-daemonset.yml
```

### 2. Install SOCNI with K3s-Specific Paths

Modify your SOCNI installation to respect K3s paths:

```bash
# Set K3s-specific paths for SOCNI
export CNI_BIN_DIR=/var/lib/rancher/k3s/data/current/bin
export CNI_CONF_DIR=/var/lib/rancher/k3s/agent/etc/cni/net.d

# Install SOCNI
./socni/scripts/install-cni.sh
```

### 3. Configure SOCNI to Work with Flannel

Ensure your `NetworkAttachmentDefinition` is appropriately configured:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vlan100-network
  namespace: secure-zone-1
spec:
  config: '{
    "cniVersion": "1.0.0",
    "type": "vlan",
    "master": "eth0",
    "vlan": 100,
    "ipam": {
      "type": "host-local",
      "subnet": "10.100.0.0/24",
      "routes": [
        { "dst": "10.100.0.0/16" }
      ]
    }
  }'
```

Note the routes configuration - we're not setting a default route to avoid conflicting with Flannel's routing.

### 4. Ensure Flannel Compatibility with Host VLAN Interfaces

K3s's Flannel may need additional configuration to properly handle host VLAN interfaces:

```bash
# Create a ConfigMap for Flannel configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: flannel-config
  namespace: kube-system
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "1.0.0",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
EOF
```

### 5. Create an Example Pod Using Both Networks

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dual-net-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: vlan100-network
spec:
  containers:
  - name: dual-net-container
    image: busybox
    command: ["/bin/sh", "-c", "trap : TERM INT; sleep infinity & wait"]
    securityContext:
      privileged: true
```

## Using SOCNI-CTL with K3s

When using `socni-ctl` in a K3s environment, you need to point it to the K3s-specific paths:

```bash
# List VLANs
socni-ctl --config-dir /var/lib/rancher/k3s/agent/etc/cni/net.d list

# Create a new VLAN with tenant isolation
socni-ctl --config-dir /var/lib/rancher/k3s/agent/etc/cni/net.d \
  --tenant-id admin create --id 200 --master eth0 --label environment=production

# Generate K3s-specific network configuration
socni-ctl generate --id 200 --master eth0 --subnet 10.200.0.0/24 \
  --output /var/lib/rancher/k3s/agent/etc/cni/net.d/200-vlan.conflist
```

## Architectural Benefits in K3s Environments

Using SOCNI with Flannel in K3s provides several key advantages:

1. **Leverages Flannel's Simplicity**: Keeps the default K3s networking for basic connectivity
2. **Adds Isolation Where Needed**: Provides strong isolation only for workloads that require it
3. **Edge-Friendly**: Works well in edge/IoT scenarios where K3s is often deployed
4. **Low Resource Overhead**: Doesn't replace the efficient Flannel implementation
5. **Upgrade Safety**: Won't break during K3s upgrades since it's a separate plugin

## Specific Transport Layer Governance Benefits

In a K3s environment, this architecture enables:

1. **Edge Network Segmentation**: Create isolated VLANs for different edge devices or sensors
2. **Multi-Tenant Edge**: Run multiple tenant workloads on resource-constrained edge nodes
3. **OT-IT Boundary Control**: Create clear boundaries between operational technology networks and IT networks
4. **Field Security**: Deploy cryptographically-verified transport layer controls to remote sites

By keeping Flannel for regular cluster traffic and adding SOCNI for secured VLAN traffic, you get the best of both worlds: K3s's lightweight efficiency with Aranya's strong cryptographic isolation where needed.
