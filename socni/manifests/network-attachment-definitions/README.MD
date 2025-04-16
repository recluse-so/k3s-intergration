# NADS

When a pod requests this network attachment (by adding the annotation k8s.v1.cni.cncf.io/networks: vlan100-network), Multus will:

Create a VLAN-tagged interface based on the node's eth0 interface
Move this interface into the pod's network namespace
Configure the interface with an IP address from the 10.100.0.0/24 subnet
Set up appropriate routing

This mechanism ensures that pods in the "secure-zone-1" namespace can be attached to VLAN 100, with all their traffic through this interface properly tagged and isolated from other VLANs. The pod will maintain its default Kubernetes network interface for cluster communication while having this additional interface for VLAN-specific traffic.
