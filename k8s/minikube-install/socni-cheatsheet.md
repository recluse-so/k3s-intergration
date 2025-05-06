# SoCNI Functionality Cheatsheet

## Prerequisites
- Minikube running with Docker driver
- kubectl configured to use Minikube
- SoCNI installed and running

## Basic Checks

### 1. Check SoCNI Pod Status
```bash
# Check if SoCNI pods are running
kubectl get pods -n kube-system | grep vlan-cni

# View detailed pod information
kubectl describe pod -n kube-system -l app=vlan-cni
```

### 2. Check SoCNI Logs
```bash
# View recent logs
kubectl logs -n kube-system -l app=vlan-cni --tail=50

# Follow logs in real-time
kubectl logs -n kube-system -l app=vlan-cni -f
```

### 3. Check SoCNI CLI Tool
```bash
# Check SoCNI CLI tool status
minikube ssh "socni-ctl status"

# View available networks
minikube ssh "socni-ctl list-networks"
```

## Network Configuration

### 1. Check CNI Configuration
```bash
# View CNI configuration
minikube ssh "cat /etc/cni/net.d/10-socni.conflist"

# Check CNI binary
minikube ssh "ls -l /opt/cni/bin/vlan"
```

### 2. Check Network Namespaces
```bash
# List network namespaces
minikube ssh "ip netns list"

# View namespace details
minikube ssh "ip netns exec <namespace> ip addr"
```

## Testing VLAN Functionality

### 1. Create Test Pods
```bash
# Create pod with VLAN 100
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan-pod
  annotations:
    socni.network.aranya.io/tenant-id: "test"
    socni.network.aranya.io/vlan: "100"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF

# Create pod with VLAN 200
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-vlan-pod-2
  annotations:
    socni.network.aranya.io/tenant-id: "test"
    socni.network.aranya.io/vlan: "200"
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
EOF
```

### 2. Verify Pod Network
```bash
# Check pod IP addresses
kubectl get pod test-vlan-pod test-vlan-pod-2 -o wide

# View network interfaces in pod
kubectl exec -it test-vlan-pod -- ip addr

# Test connectivity to gateway
kubectl exec -it test-vlan-pod -- ping -c 3 10.100.0.1
```

### 3. Test VLAN Isolation
```bash
# Get IP of second pod
POD2_IP=$(kubectl get pod test-vlan-pod-2 -o jsonpath='{.status.podIP}')

# Attempt to ping between pods (should fail)
kubectl exec -it test-vlan-pod -- ping -c 3 $POD2_IP
```

## Troubleshooting

### 1. Check Network Policies
```bash
# View Aranya policies
minikube ssh "cat /var/lib/aranya/config.json"

# Check Aranya daemon status
minikube ssh "ps aux | grep aranya-daemon"
```

### 2. Check Network Routes
```bash
# View routes in pod
kubectl exec -it test-vlan-pod -- ip route

# Check VLAN interfaces
minikube ssh "ip link show type vlan"
```

### 3. Check System Logs
```bash
# View system logs for network events
minikube ssh "journalctl -u kubelet | grep socni"

# Check CNI plugin logs
minikube ssh "cat /var/log/socni.log"
```

## Cleanup
```bash
# Delete test pods
kubectl delete pod test-vlan-pod test-vlan-pod-2

# Restart SoCNI daemonset
kubectl rollout restart daemonset -n kube-system vlan-cni

# Clean all SoCNI resources
kubectl delete -f manifests/daemonset.yaml
kubectl delete -f deployments/network-attachment-definitions/
```

## Common Issues and Solutions

1. **Pods stuck in ContainerCreating**
   - Check SoCNI logs
   - Verify CNI configuration
   - Ensure Aranya daemon is running

2. **VLAN isolation not working**
   - Verify VLAN IDs in pod annotations
   - Check Aranya policies
   - Verify network namespace configuration

3. **Network connectivity issues**
   - Check pod IP addresses
   - Verify routes
   - Test gateway connectivity

4. **SoCNI CLI tool not responding**
   - Check if daemon is running
   - Verify socket permissions
   - Restart SoCNI daemonset 