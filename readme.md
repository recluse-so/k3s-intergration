# CNI Plugin Overview

The Go implementation of the VLAN CNI plugin for Kubernetes is designed with a clean architecture that enables VLAN networking capabilities on both wired and wireless (WLAN) host interfaces. Let me elaborate on the architecture and how it specifically handles VLAN on WLAN integration:

### Core Architecture Components

1. **Plugin Entry Point (`cmd/vlan-cni/main.go`)**:
   - Implements the standard CNI plugin interface (ADD, DEL, CHECK operations)
   - Parses configuration and delegates to the implementation layers
   - Serves as the minimal entry point that follows CNI specification

2. **Configuration Management (`pkg/config/config.go`)**:
   - Defines the plugin's configuration structure
   - Handles parsing and validating VLAN-specific parameters
   - Includes wireless-specific configurations for WLAN interfaces

3. **VLAN Implementation (`pkg/plugin/vlan.go`)**:
   - Core network implementation that creates and configures VLAN interfaces
   - Handles both wired and wireless parent interfaces
   - Contains logic to detect interface types and apply appropriate configurations

4. **IPAM Integration (`pkg/plugin/ipam.go`)**:
   - Manages IP address allocation and routing
   - Works with standard CNI IPAM plugins (host-local, DHCP, static)

### VLAN on WLAN Specific Architecture

When implementing VLANs over wireless networks (WLANs), several unique challenges need to be addressed:

1. **Wireless Interface Detection**:
   The plugin automatically detects when the master interface is a wireless interface by:

   ```go
   // In pkg/plugin/vlan.go
   func isWirelessInterface(ifaceName string) bool {
       // Check if the interface is in /sys/class/net/<iface>/wireless/
       if _, err := os.Stat(fmt.Sprintf("/sys/class/net/%s/wireless", ifaceName)); err == nil {
           return true
       }
       return false
   }
   ```

2. **WLAN-specific VLAN Implementation**:
   For wireless interfaces, the plugin uses a different approach since not all wireless drivers support direct VLAN tagging:

   ```go
   // Special handling for wireless interfaces
   if isWirelessInterface(master.Attrs().Name) {
       // Use 802.1q over 802.11 (4-address mode) if supported
       // or fallback to software bridging
       if supportsWireless80211QMode(master) {
           vlan = createWireless80211QVlan(master, conf.VlanID)
       } else {
           vlan = createSoftwareVlanForWireless(master, conf.VlanID)
       }
   } else {
       // Standard VLAN creation for wired interfaces
       vlan = &netlink.Vlan{
           LinkAttrs: netlink.LinkAttrs{
               Name:        vlanName,
               ParentIndex: master.Attrs().Index,
               MTU:         conf.MTU,
           },
           VlanId: conf.VlanID,
       }
   }
   ```

3. **Multi-mode Support**:
   The plugin implements multiple approaches to VLAN over WLAN:

   a. **4-Address Mode** (when supported):

   ```go
   func createWireless80211QVlan(master netlink.Link, vlanID int) netlink.Link {
       // Implement 4-address mode (802.1q over 802.11)
       // This requires driver support and may need special iw/iproute2 commands
       // ...implementation details...
   }
   ```

   b. **Software Bridge Fallback**:

   ```go
   func createSoftwareVlanForWireless(master netlink.Link, vlanID int) netlink.Link {
       // Create bridge and virtual interfaces for software VLAN tagging
       // ...implementation details...
   }
   ```

4. **Driver-specific Adaptations**:
   The plugin includes detection and configuration for common wireless drivers:

   ```go
   func configureWirelessDriver(master netlink.Link, vlanID int) error {
       driverInfo, err := getWirelessDriverInfo(master.Attrs().Name)
       if err != nil {
           return err
       }
   
       switch driverInfo.driverName {
       case "ath9k", "ath10k":
           return configureAtherosDriver(master.Attrs().Name, vlanID)
       case "iwlwifi":
           return configureIntelDriver(master.Attrs().Name, vlanID)
       // ...other drivers...
       default:
           return useGenericConfiguration(master.Attrs().Name, vlanID)
       }
   }
   ```

### Key Technical Components for WLAN Support

1. **Wireless Mode Configuration**:
   - For interfaces that support it, configures the wireless interface in the "4-address mode" which is needed for VLAN tagging on wireless links
   - Uses appropriate `iw` commands to set this mode

2. **MTU Handling**:
   - Manages MTU differences between wired and wireless interfaces
   - Accounts for VLAN tag overhead in wireless environments

3. **Performance Optimization**:
   - Includes TX queue tuning for wireless interfaces
   - Implements appropriate QoS mapping between 802.1p priorities and wireless QoS categories

4. **Driver Detection and Configuration**:
   - Detects the wireless driver in use
   - Applies driver-specific optimizations for VLAN support

5. **Fallback Mechanisms**:
   - If direct VLAN tagging isn't supported, uses software-based alternatives
   - Provides multi-level fallback strategies for maximum compatibility

### Interface with Kubernetes

The architecture seamlessly integrates with Kubernetes through:

1. **Node Feature Discovery**:
   - The install script detects wireless capabilities and labels nodes appropriately
   - Adds labels like `networking/wireless-vlan-capable: "true"` when WLAN VLAN is supported

2. **Pod Scheduling**:
   - NetworkAttachmentDefinition resources can specify WLAN-specific parameters
   - Pod scheduling can target nodes with appropriate wireless+VLAN capabilities

3. **Runtime Configuration**:
   - Supports dynamic reconfiguration for wireless parameters
   - Adapts to changes in wireless connectivity

This architecture allows the CNI plugin to provide VLAN isolation regardless of whether the underlying physical network is wired or wireless, offering flexibility for diverse Kubernetes deployments including edge and IoT scenarios where wireless connectivity is common.

## Impact on Regular Kubernetes Networking

The VLAN CNI plugin operates as a **secondary network** alongside the standard Kubernetes network rather than replacing it. This approach has several important implications:

1. **Default Kubernetes Network Remains Intact**:
   - The cluster's primary CNI plugin (like Calico, Flannel, or Cilium) continues to function normally
   - All pods still receive their primary network interface for regular Kubernetes networking
   - Service discovery, kube-proxy, and other standard networking features work as usual

2. **Multi-Network Architecture**:
   - The VLAN interfaces are provided as additional network interfaces to pods
   - Pods maintain their default Kubernetes network interface (`eth0`) and gain a secondary interface (e.g., `net1`) for VLAN traffic

3. **Traffic Routing Options**:
   - By default, pod-to-pod and pod-to-service traffic still flows through the primary Kubernetes network
   - Only traffic specifically targeted for external systems or other VLAN-attached resources uses the VLAN interfaces

### Impact on Namespaces and Workloads

When you create different namespaces and deploy workloads:

1. **Enhanced Rather Than Different**:
   - The fundamental Kubernetes networking model isn't changed
   - Namespaces still have logical isolation at the Kubernetes level
   - The VLAN interfaces provide additional physical network isolation

2. **Opt-in Architecture**:
   - Only pods that explicitly request VLAN attachments (via annotations) get the secondary interfaces
   - Pods without VLAN annotations operate exactly as they would in standard Kubernetes

3. **Namespace-Level Isolation**:
   - You can restrict which VLANs are accessible from which namespaces
   - NetworkAttachmentDefinitions can be namespace-scoped, providing additional security boundaries

### Example Scenario

For example, if you have three namespaces (`default`, `secure-zone-1`, and `secure-zone-2`):

1. **Default Namespace**:
   - Pods in this namespace use only standard Kubernetes networking
   - They communicate via the cluster's service network as usual

2. **Secure-Zone-1 Namespace** (with VLAN 100 access):
   - Pods that include the annotation `k8s.v1.cni.cncf.io/networks: vlan100-network` get:
     - Regular Kubernetes network interface for cluster communication
     - Additional VLAN 100 interface for direct external network access on VLAN 100
   - Pods without this annotation behave like regular Kubernetes pods

3. **Secure-Zone-2 Namespace** (with VLAN 200 access):
   - Similarly, annotated pods get VLAN 200 access
   - This creates physical network separation between workloads in different secure zones

### Key Considerations

1. **Routing Complexity**:
   - Pods with multiple interfaces need careful route management (which is handled by the CNI)
   - Default routes are typically maintained on the primary Kubernetes interface

2. **Service Mesh Integration**:
   - If using a service mesh like Istio, the VLAN traffic bypasses the mesh by default
   - This can be an advantage or disadvantage depending on your security requirements

3. **NetworkPolicy Application**:
   - Kubernetes NetworkPolicies apply to the primary interface but may not control VLAN traffic
   - Additional security measures may be needed for VLAN interfaces

The fundamental networking isn't different - it's extended with physical network isolation capabilities. This approach gives you the best of both worlds: Kubernetes' powerful service discovery and network abstraction plus the security and isolation benefits of VLAN segmentation.


## How SOCNI and Aranya Enable Transport Layer Governance

Your implementation of SOCNI (Secure Overlay CNI) with Aranya provides a comprehensive framework for governing the transport layer in multi-tenant Kubernetes environments. Here's how teams can use this solution to effectively control and secure their network transport:

## 1. Physical Network Isolation through VLANs

The VLAN CNI plugin provides Layer 2 isolation at the transport layer, ensuring complete separation of network traffic between tenants:

```bash
# Create isolated VLAN for a team
socni-ctl --tenant-id admin create --id 100 --master eth0 --label team=engineering
```

This creates a dedicated VLAN segment that isolates traffic at the Ethernet frame level, preventing any cross-team traffic leakage at the transport layer. Each VLAN operates as a separate broadcast domain, with traffic physically segregated on the wire.

## 2. Cryptographic Access Control for Transport Layer Resources

The integration with Aranya's cryptographic policy engine ensures that only authorized tenants can create or access specific VLANs:

```json
{
  "id": "engineering_transport_access",
  "subjects": ["tenant:engineering"],
  "permissions": ["sdwan:access_vlan:100", "sdwan:access_vlan:101"],
  "effect": "allow"
}
```

This policy allows the engineering tenant to access only their authorized VLANs (100 and 101). The critical difference from traditional access control is that Aranya enforces this with cryptographic verification, making it mathematically verifiable and significantly more secure than traditional ACLs.

## 3. Zero-Trust Transport Layer with Identity-Based Controls

Teams can implement a zero-trust approach to the transport layer where every connection attempt is verified against cryptographic tenant identities and VLAN access rights:

```rust
// Extract from your VlanPlugin implementation
if !self.check_tenant_access(&mapped_tenant, self.config.vlan)? {
    anyhow::bail!("Access denied: tenant {} is not allowed to access VLAN {}", 
                 mapped_tenant, self.config.vlan);
}
```

This validation happens before any network resources are allocated, ensuring that unauthorized tenants cannot even attempt to access transport layer resources they don't have permission for.

## 4. Microsegmentation with Fine-Grained VLAN Controls

Teams can create multiple VLANs for different application tiers and control access to each specifically:

```bash
# Create segmented VLANs for different application tiers
socni-ctl --tenant-id admin create --id 110 --master eth0 --label tier=web
socni-ctl --tenant-id admin create --id 120 --master eth0 --label tier=app
socni-ctl --tenant-id admin create --id 130 --master eth0 --label tier=database

# Grant specific access rights to each tenant
socni-ctl --tenant-id admin grant --vlan-id 110 --target-tenant web-team
socni-ctl --tenant-id admin grant --vlan-id 120 --target-tenant app-team
socni-ctl --tenant-id admin grant --vlan-id 130 --target-tenant db-team
```

This microsegmentation approach allows teams to implement the principle of least privilege at the transport layer, where application components only have access to the network segments they absolutely need.

## 5. Auditable Transport Layer Governance

All transport layer access decisions are logged and verifiable:

```yaml
logging:
  level: info
  audit: true
policy:
  default_effect: deny
  audit_all_decisions: true
```

This provides teams with a comprehensive audit trail of all transport layer access attempts, successful or not, which is essential for security governance and compliance requirements.

## 6. Cross-Team Collaboration with Controlled Shared Transport

When cross-team collaboration is needed, shared VLANs can be created with precise access controls:

```bash
# Create a shared VLAN for collaboration
socni-ctl --tenant-id admin create --id 999 --master eth0 --label purpose=collaboration

# Grant access to multiple teams
socni-ctl --tenant-id admin grant --vlan-id 999 --target-tenant team-a
socni-ctl --tenant-id admin grant --vlan-id 999 --target-tenant team-b
```

This provides a controlled exception to the strict isolation, allowing teams to collaborate when necessary while maintaining governance over the shared transport layer.

## 7. Integration with Kubernetes Networking Abstractions

Teams can manage transport layer controls directly through Kubernetes abstractions:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: secure-network-zone
  namespace: team-finance
spec:
  config: '{
    "cniVersion": "1.0.0",
    "type": "vlan",
    "master": "eth0",
    "vlan": 100,
    "aranya": {
      "tenant_id": "finance"
    }
  }'
```

This allows teams to declaratively define their transport layer requirements as part of their Kubernetes manifests, bringing transport layer governance into the GitOps workflow.

## 8. Centralized Transport Governance with Distributed Enforcement

The architecture enables a centralized policy definition with distributed enforcement:

1. **Central Policy Definition**: Security teams define tenant access policies centrally
2. **Node-Level Enforcement**: The CNI plugin enforces these policies on every node
3. **Tenant-Level Control**: Teams manage their assigned transport resources within their boundaries

This multi-level governance model ensures the transport layer is managed according to organization-wide security requirements while still allowing teams flexibility within their authorized boundaries.

## Real-World Impact

In practical terms, this solution gives infrastructure and security teams unprecedented control over the transport layer:

1. **Network Segmentation**: Complete isolation between different teams or applications
2. **Regulatory Compliance**: Ability to enforce and prove network isolation for regulated data
3. **Attack Surface Reduction**: Elimination of potential lateral movement between tenant networks
4. **Zero-Trust Implementation**: Identity-verified access to every network segment
5. **Physical Layer Protection**: Isolation all the way down to the Ethernet frame level

The combination of VLAN-based isolation with Aranya's cryptographic policy enforcement creates a uniquely secure and governable transport layer that goes beyond traditional SDN approaches by adding cryptographic verification to all access decisions.
