# Kubernetes VLAN CNI Project Structure and Files


This implementation provides:

VLAN tagging and segregation at the container network interface level
Namespace-to-VLAN mapping
Node-level physical infrastructure integration
Simple pod annotations for attaching to specific VLANs


## Key File Contents

### 1. CNI Plugin Implementation

The main plugin logic is in pkg/plugin/vlan.go, which handles creating VLAN interfaces, moving them to container namespaces, and configuring IP addressing.
Configuration parsing in pkg/config/config.go validates VLAN parameters.

### 2. Kubernetes Deployment Manifest

DaemonSet deployment ensures the CNI binary is available on every node.
NetworkAttachmentDefinition resources define VLAN networks that pods can attach to.
Example pod configurations show how workloads can request specific VLAN networks.


### 3. Network Attachment Definition Example

The Network Attachment Definition (NAD) is a Custom Resource Definition (CRD) provided by the Multus CNI project, which enables attaching multiple network interfaces to Kubernetes pods. This is essential for implementing VLAN isolation in Kubernetes because it allows pods to connect to specific VLANs through additional network interfaces beyond the default pod network.

This mechanism ensures that pods in the "secure-zone-1" namespace can be attached to VLAN 100, with all their traffic through this interface properly tagged and isolated from other VLANs. The pod will maintain its default Kubernetes network interface for cluster communication while having this additional interface for VLAN-specific traffic.

### 4. Example Pod Using VLAN Network



### 5. Dockerfile for Building CNI Plugin


### 6. Makefile


### 7. Module Definition

