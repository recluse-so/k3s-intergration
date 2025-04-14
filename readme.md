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
