# Aranya CNI Integration Guide

## Overview

Aranya provides a policy-driven approach to network configuration in Kubernetes through its CNI plugin. This guide explains how to integrate Aranya with Kubernetes and use policies to control network behavior.

## Prerequisites

- Kubernetes cluster (minikube or other)
- Aranya daemon running
- SoCNI plugin installed
- kubectl configured

## Installation Steps

1. **Install Aranya Daemon**
```bash
# Build Aranya
cd /Users/asaunders/githubRepos/k3s-intergration/aranya
cargo build --release

# Start Aranya daemon
sudo /Users/asaunders/githubRepos/k3s-intergration/aranya/target/release/aranya-daemon /var/lib/aranya/config.json
```

2. **Configure CNI**
```bash
# Create CNI configuration
cat > /etc/cni/net.d/10-socni.conflist <<EOF
{
  "cniVersion": "0.3.1",
  "name": "socni",
  "plugins": [
    {
      "type": "socni",
      "daemonSocket": "/var/run/aranya/aranya.sock",
      "policyPath": "/var/lib/aranya/policies"
    }
  ]
}
EOF
```

## Policy-Based Configuration

### 1. Network Policies

Aranya uses policies to define network behavior. Create policies in `/var/lib/aranya/policies/`:

```json
// Example: tenant-isolation.json
{
  "name": "tenant-isolation",
  "rules": [
    {
      "match": {
        "tenant_id": "tenant1"
      },
      "action": {
        "vlan": 100,
        "encryption": "required",
        "allowed_peers": ["tenant1"]
      }
    }
  ]
}
```

### 2. Pod Annotations

Apply policies through pod annotations:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tenant1-pod
  annotations:
    socni.network.aranya.io/tenant-id: "tenant1"
    socni.network.aranya.io/policy: "tenant-isolation"
spec:
  containers:
  - name: test
    image: busybox
```

### 3. Network Attachment Definitions

Create NetworkAttachmentDefinition CRDs for policy-based networks:

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: tenant1-network
  annotations:
    socni.network.aranya.io/policy: "tenant-isolation"
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "socni",
    "name": "tenant1-network",
    "daemonSocket": "/var/run/aranya/aranya.sock"
  }'
```

## Policy Types

1. **Tenant Isolation**
   - Controls communication between tenants
   - Enforces VLAN separation
   - Manages encryption requirements

2. **Network Access**
   - Defines allowed network paths
   - Controls external connectivity
   - Manages routing policies

3. **Security Policies**
   - Enforces encryption requirements
   - Controls certificate validation
   - Manages authentication

## Example Use Cases

### 1. Multi-tenant Network Isolation

```yaml
# Policy: multi-tenant.json
{
  "name": "multi-tenant",
  "rules": [
    {
      "match": {
        "tenant_id": "tenant1"
      },
      "action": {
        "vlan": 100,
        "encryption": "required",
        "allowed_peers": ["tenant1"]
      }
    },
    {
      "match": {
        "tenant_id": "tenant2"
      },
      "action": {
        "vlan": 200,
        "encryption": "required",
        "allowed_peers": ["tenant2"]
      }
    }
  ]
}

# Pod using the policy
apiVersion: v1
kind: Pod
metadata:
  name: tenant1-app
  annotations:
    socni.network.aranya.io/tenant-id: "tenant1"
    socni.network.aranya.io/policy: "multi-tenant"
spec:
  containers:
  - name: app
    image: nginx
```

### 2. Secure Service Communication

```yaml
# Policy: secure-service.json
{
  "name": "secure-service",
  "rules": [
    {
      "match": {
        "service": "database"
      },
      "action": {
        "vlan": 300,
        "encryption": "required",
        "allowed_peers": ["application"],
        "certificate_validation": "strict"
      }
    }
  ]
}

# Service using the policy
apiVersion: v1
kind: Service
metadata:
  name: database
  annotations:
    socni.network.aranya.io/policy: "secure-service"
spec:
  selector:
    app: database
  ports:
  - port: 5432
```

## Monitoring and Troubleshooting

1. **Check Policy Status**
```bash
# View active policies
kubectl get networkpolicies

# Check policy enforcement
kubectl describe networkpolicy <policy-name>
```

2. **Monitor Network Traffic**
```bash
# View network interfaces
kubectl exec -it <pod-name> -- ip addr

# Check VLAN configuration
kubectl exec -it <pod-name> -- ip link show type vlan
```

3. **Verify Encryption**
```bash
# Check TLS certificates
kubectl exec -it <pod-name> -- openssl s_client -connect <service>:<port>

# Verify certificate chain
kubectl exec -it <pod-name> -- openssl verify -CAfile /var/lib/aranya/keystore/ca.crt /var/lib/aranya/keystore/client.crt
```

## Best Practices

1. **Policy Management**
   - Use version control for policies
   - Test policies in non-production environments
   - Document policy changes

2. **Security**
   - Regularly rotate certificates
   - Use strong encryption algorithms
   - Monitor policy compliance

3. **Performance**
   - Optimize policy rules
   - Monitor network overhead
   - Use appropriate VLAN configurations

## Troubleshooting

1. **Common Issues**
   - Policy not applied: Check annotations and policy file
   - Network connectivity: Verify VLAN configuration
   - Encryption issues: Check certificates and keys

2. **Debug Commands**
```bash
# Check Aranya daemon logs
journalctl -u aranya-daemon

# Verify CNI configuration
cat /etc/cni/net.d/10-socni.conflist

# Check policy enforcement
kubectl describe pod <pod-name>
```

## Next Steps

1. Implement monitoring for policy compliance
2. Set up automated policy testing
3. Configure backup and recovery procedures
4. Document operational procedures 