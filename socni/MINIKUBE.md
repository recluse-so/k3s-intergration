# SOCNI Minikube Installation Cheatsheet

This cheatsheet provides step-by-step instructions for installing and testing SOCNI in a Minikube environment.

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) v1.28.0 or later
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.24.0 or later
- [Docker](https://docs.docker.com/get-docker/) or [VirtualBox](https://www.virtualbox.org/wiki/Downloads)
- [Git](https://git-scm.com/downloads)
- [Make](https://www.gnu.org/software/make/)

## Quick Start

```bash
# Start Minikube with the appropriate driver
minikube start --driver=docker --network-plugin=cni --cni=calico

# Clone the SOCNI repository
git clone https://github.com/username/socni.git
cd socni

# Build SOCNI
make build

# Install SOCNI in Minikube
minikube cp bin/vlan minikube:/opt/cni/bin/
minikube cp bin/socni-ctl minikube:/usr/local/bin/
minikube ssh "sudo chmod +x /opt/cni/bin/vlan /usr/local/bin/socni-ctl"

# Deploy SOCNI to Minikube
make deploy

# Create network attachment definitions
make create-networks

# Verify installation
kubectl get pods -n kube-system | grep socni
```

## Detailed Installation

### 1. Start Minikube with CNI Support

```bash
# Start Minikube with Docker driver and Calico CNI
minikube start --driver=docker --network-plugin=cni --cni=calico

# Verify Minikube is running
minikube status
```

### 2. Build SOCNI

```bash
# Clone the repository
git clone https://github.com/username/socni.git
cd socni

# Build the binaries
make build
```

### 3. Install SOCNI in Minikube

```bash
# Copy the CNI plugin to Minikube
minikube cp bin/vlan minikube:/opt/cni/bin/

# Copy the CLI tool to Minikube
minikube cp bin/socni-ctl minikube:/usr/local/bin/

# Make the binaries executable
minikube ssh "sudo chmod +x /opt/cni/bin/vlan /usr/local/bin/socni-ctl"

# Create CNI configuration directory if it doesn't exist
minikube ssh "sudo mkdir -p /etc/cni/net.d"
```

### 4. Create CNI Configuration

```bash
# Create a basic CNI configuration
cat << EOF | minikube ssh "sudo tee /etc/cni/net.d/10-socni.conflist"
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
EOF
```

### 5. Deploy SOCNI to Minikube

```bash
# Deploy the DaemonSet
make deploy

# Create network attachment definitions
make create-networks
```

### 6. Verify Installation

```bash
# Check if SOCNI pods are running
kubectl get pods -n kube-system | grep socni

# Check SOCNI logs
kubectl logs -n kube-system -l app=socni

# Test SOCNI CLI tool
minikube ssh "socni-ctl status"
```

## Testing SOCNI

### 1. Create a Test Pod with VLAN Network

```bash
# Create a test pod with VLAN network
cat << EOF | kubectl apply -f -
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
```

### 2. Verify Pod Networking

```bash
# Wait for the pod to be ready
kubectl wait --for=condition=Ready pod/test-vlan-pod

# Check pod IP address
kubectl get pod test-vlan-pod -o wide

# Execute commands in the pod
kubectl exec -it test-vlan-pod -- ip addr
kubectl exec -it test-vlan-pod -- ping -c 3 10.100.0.1
```

### 3. Test VLAN Isolation

```bash
# Create another pod on a different VLAN
cat << EOF | kubectl apply -f -
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

# Wait for the pod to be ready
kubectl wait --for=condition=Ready pod/test-vlan-pod-2

# Try to ping between pods (should fail due to VLAN isolation)
kubectl exec -it test-vlan-pod -- ping -c 3 $(kubectl get pod test-vlan-pod-2 -o jsonpath='{.status.podIP}')
```

## Troubleshooting

### Common Issues

1. **CNI Plugin Not Found**:
   ```bash
   # Check if the CNI plugin is installed
   minikube ssh "ls -la /opt/cni/bin/vlan"
   
   # Check CNI configuration
   minikube ssh "cat /etc/cni/net.d/10-socni.conflist"
   ```

2. **Pod Network Issues**:
   ```bash
   # Check CNI logs
   minikube ssh "journalctl -t socni-cni -n 50"
   
   # Check pod events
   kubectl describe pod test-vlan-pod
   ```

3. **Aranya Connection Issues**:
   ```bash
   # Check if Aranya daemon is running
   minikube ssh "systemctl status aranya || echo 'Aranya not installed'"
   
   # Check Aranya logs
   minikube ssh "journalctl -t aranya -n 50 || echo 'No Aranya logs'"
   ```

### Debugging Commands

```bash
# SSH into Minikube
minikube ssh

# Check CNI plugin status
socni-ctl status

# Check network interfaces
ip link show

# Check CNI configuration
cat /etc/cni/net.d/10-socni.conflist

# Check CNI logs
journalctl -t socni-cni -f
```

## Cleanup

```bash
# Delete test pods
kubectl delete pod test-vlan-pod test-vlan-pod-2

# Delete SOCNI resources
kubectl delete -f manifests/daemonset.yaml
kubectl delete -f deployments/network-attachment-definitions/

# Stop Minikube
minikube stop

# Delete Minikube cluster
minikube delete
```

## Additional Resources

- [SOCNI Documentation](README.md)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Kubernetes CNI Documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Aranya Security Documentation](https://aranya.io/docs) 