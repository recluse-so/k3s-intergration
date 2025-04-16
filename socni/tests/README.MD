# Using Aranya Policies for Multi-Tenant VLAN Architecture

To implement multi-tenant architecture with strict isolation using Aranya policies and your VLAN CNI plugin, follow these steps:

## 1. Define a Comprehensive Policy Structure

Create a policy file that defines tenant boundaries and VLAN access rights:

```json
{
  "version": "1.0",
  "policy_name": "multi_tenant_vlan_policy",
  "rules": [
    {
      "id": "system_admin_access",
      "subjects": ["tenant:system-admin"],
      "permissions": ["sdwan:admin"],
      "effect": "allow",
      "description": "System administrators have full access to all VLANs and operations"
    },
    {
      "id": "tenant_admin_operations",
      "subjects": ["role:tenant-admin"],
      "permissions": [
        "sdwan:list_vlans", 
        "sdwan:create_vlan_within_tenant",
        "sdwan:grant_vlan_access_within_tenant"
      ],
      "effect": "allow",
      "description": "Tenant administrators can manage VLANs within their tenant"
    },
    {
      "id": "tenant_isolation",
      "subjects": ["tenant:*"],
      "permissions": ["sdwan:access_tenant_*"],
      "effect": "deny",
      "description": "By default, tenants cannot access other tenants' resources"
    },
    {
      "id": "tenant_specific_vlans",
      "subjects": ["tenant:finance"],
      "permissions": [
        "sdwan:access_vlan:100",
        "sdwan:access_vlan:101" 
      ],
      "effect": "allow",
      "description": "Finance tenant can access specific VLANs"
    },
    {
      "id": "tenant_specific_vlans_hr",
      "subjects": ["tenant:hr"],
      "permissions": [
        "sdwan:access_vlan:200",
        "sdwan:access_vlan:201"
      ],
      "effect": "allow",
      "description": "HR tenant can access specific VLANs"
    },
    {
      "id": "shared_services_vlan",
      "subjects": ["tenant:*"],
      "permissions": ["sdwan:access_vlan:999"],
      "effect": "allow",
      "description": "All tenants can access the shared services VLAN"
    }
  ]
}
```

## 2. Integrate the Policy with Aranya Daemon

Save this policy to an Aranya policy file and load it:

```bash
# Assuming Aranya is installed
sudo mkdir -p /etc/aranya/policies
sudo vim /etc/aranya/policies/multi_tenant_vlan.json
# Paste the policy JSON

# Then load the policy (implementation depends on your Aranya setup)
sudo aranya-ctl policy load /etc/aranya/policies/multi_tenant_vlan.json
```

## 3. Create a Tenant-to-VLAN Mapping in Kubernetes

Create a ConfigMap to store the tenant-to-VLAN mapping:

```yaml
# tenant-vlan-mapping.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tenant-vlan-mapping
  namespace: kube-system
data:
  mapping: |
    {
      "tenants": {
        "finance": {
          "vlans": [100, 101],
          "namespaces": ["finance", "accounting"]
        },
        "hr": {
          "vlans": [200, 201],
          "namespaces": ["hr", "recruiting"]
        },
        "shared": {
          "vlans": [999],
          "namespaces": ["shared-services"]
        }
      }
    }
```

Apply it to your cluster:

```bash
kubectl apply -f tenant-vlan-mapping.yaml
```

## 4. Create NetworkAttachmentDefinitions for Each VLAN

```yaml
# finance-vlans.yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: finance-vlan-100
  namespace: finance
spec:
  config: '{
    "cniVersion": "1.0.0",
    "name": "finance-vlan-100",
    "type": "vlan",
    "master": "eth0",
    "vlan": 100,
    "ipam": {
      "type": "host-local",
      "subnet": "10.100.0.0/24",
      "gateway": "10.100.0.1"
    },
    "aranya": {
      "tenant_id": "finance"
    }
  }'
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: finance-vlan-101
  namespace: finance
spec:
  config: '{
    "cniVersion": "1.0.0",
    "name": "finance-vlan-101",
    "type": "vlan",
    "master": "eth0",
    "vlan": 101,
    "ipam": {
      "type": "host-local",
      "subnet": "10.101.0.0/24",
      "gateway": "10.101.0.1"
    },
    "aranya": {
      "tenant_id": "finance"
    }
  }'
```

Do the same for the HR VLANs and shared VLAN.

## 5. Create an Admission Controller or Mutating Webhook

This component will:
1. Intercept pod creation requests
2. Verify the pod's namespace against the tenant mapping
3. Enforce Aranya policy checks before allowing VLAN attachments

Here's a simplified pseudocode for the webhook logic:

```python
def validate_pod(request):
    pod = request.object
    namespace = pod.metadata.namespace
    
    # Check if pod has network attachment annotations
    if 'k8s.v1.cni.cncf.io/networks' in pod.metadata.annotations:
        requested_networks = parse_networks(pod.metadata.annotations['k8s.v1.cni.cncf.io/networks'])
        
        # Get tenant for this namespace
        tenant = get_tenant_for_namespace(namespace)
        if not tenant:
            return deny("Namespace not mapped to any tenant")
        
        # For each requested network
        for network in requested_networks:
            # Extract VLAN ID from NetworkAttachmentDefinition
            vlan_id = get_vlan_id_for_network(network)
            
            # Check Aranya policy
            if not aranya_client.check_permission(tenant, f"sdwan:access_vlan:{vlan_id}"):
                return deny(f"Tenant {tenant} is not allowed to access VLAN {vlan_id}")
    
    return allow()
```

## 6. Extend Your VLAN CNI Plugin

Modify your CNI plugin to check the Aranya policy before configuring VLANs:

```rust:socni/src/plugin/mod.rs
// Add this function to your VlanPlugin implementation
fn check_tenant_access(&self, tenant_id: &str, vlan_id: u16) -> Result<bool> {
    // Get Aranya socket path from env or config
    let socket_path = std::env::var("ARANYA_SOCKET")
        .unwrap_or_else(|_| "/var/run/aranya/api.sock".to_string());
    
    // Connect to Aranya daemon
    let client = AranyaClient::new(PathBuf::from(socket_path), tenant_id.to_string());
    
    // Check permission
    client.check_permission(&format!("sdwan:access_vlan:{}", vlan_id))
}

// Modify add_network to check tenant access
pub fn add_network(&self) -> Result<CniResult> {
    // Extract tenant ID from CNI args
    let tenant_id = self.args.args.get("tenant_id")
        .or_else(|| self.args.args.get("K8S_POD_NAMESPACE"))
        .unwrap_or(&"default".to_string());
    
    // Map namespace to tenant if needed using the ConfigMap data
    let mapped_tenant = self.map_namespace_to_tenant(tenant_id)?;
    
    // Check if tenant has access to this VLAN
    if !self.check_tenant_access(&mapped_tenant, self.config.vlan)? {
        anyhow::bail!("Access denied: tenant {} is not allowed to access VLAN {}", 
                     mapped_tenant, self.config.vlan);
    }
    
    // Continue with existing implementation
    // ...
}
```

## 7. Deploy Test Pods for Each Tenant

```yaml
# finance-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: finance-app
  namespace: finance
  annotations:
    k8s.v1.cni.cncf.io/networks: finance-vlan-100
spec:
  containers:
  - name: finance-app
    image: busybox
    command: ["/bin/sh", "-c", "trap : TERM INT; sleep infinity & wait"]
    securityContext:
      privileged: true
```

```yaml
# hr-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hr-app
  namespace: hr
  annotations:
    k8s.v1.cni.cncf.io/networks: hr-vlan-200
spec:
  containers:
  - name: hr-app
    image: busybox
    command: ["/bin/sh", "-c", "trap : TERM INT; sleep infinity & wait"]
    securityContext:
      privileged: true
```

## 8. Verify Isolation

Test that:
- Finance pods can access Finance VLANs but not HR VLANs
- HR pods can access HR VLANs but not Finance VLANs
- All pods can access the shared VLAN

```bash
# Check Finance pod can access VLAN 100
kubectl exec -n finance finance-app -- ip addr show

# Try to create a pod in the Finance namespace with HR VLAN (should be denied)
kubectl apply -f finance-with-hr-vlan.yaml
# This should fail due to the admission controller

# Test connectivity between pods on the same VLAN
kubectl exec -n finance finance-app -- ping <IP of another Finance pod on VLAN 100>

# Test isolation - this should fail
kubectl exec -n finance finance-app -- ping <IP of HR pod on VLAN 200>
```

## 9. Audit and Monitoring

Set up audit logging for all policy decisions:

```yaml
# aranya-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: aranya-config
  namespace: kube-system
data:
  config.yaml: |
    logging:
      level: info
      audit: true
    policy:
      default_effect: deny
      audit_all_decisions: true
```

## Key Benefits of This Architecture

1. **Cryptographic Tenant Isolation**: Aranya's crypto engine ensures truly secure tenant boundaries
2. **Policy-Based Access Control**: Centralized policy decisions with fine-grained permissions
3. **Network Segregation**: Complete VLAN isolation at the physical network level
4. **Namespace Mapping**: Leverage Kubernetes namespaces for tenant boundaries
5. **Audit Trail**: All access decisions are logged and auditable
6. **Shared Services**: Controlled ability to share specific VLANs across tenants

This architecture combines the security of Aranya's cryptographic identity system with the network isolation of VLANs to create a truly multi-tenant environment with strong boundaries between tenants.
