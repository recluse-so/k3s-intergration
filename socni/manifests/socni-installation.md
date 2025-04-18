# Installing SOCNI on Kubernetes

This guide explains how to deploy the SOCNI container on a Kubernetes cluster to provide VLAN-based network isolation with policy enforcement.

## Prerequisites

- Kubernetes cluster (1.16+)
- `kubectl` configured to communicate with your cluster
- Multus CNI plugin installed (required for multi-network support)
- Access to build and push the SOCNI container image

## Installation Steps

### 1. Build and Push the SOCNI Container Image

First, build the SOCNI container image:

```bash
# From the root of your project
docker build -t socni:latest -f socni/Dockerfile.socni .
```

Push the image to a registry accessible by your Kubernetes cluster:

```bash
# Tag the image for your registry
docker tag socni:latest your-registry.com/socni:latest

# Push to your registry
docker push your-registry.com/socni:latest
```

### 2. Apply the Kubernetes Manifests

Apply the RBAC resources first:

```bash
kubectl apply -f socni/manifests/socni-rbac.yaml
```

Apply the ConfigMap:

```bash
kubectl apply -f socni/manifests/socni-configmap.yaml
```

Apply the NetworkAttachmentDefinition:

```bash
kubectl apply -f socni/manifests/socni-network-attachment-definition.yaml
```

Finally, deploy the SOCNI DaemonSet:

```bash
kubectl apply -f socni/manifests/socni-daemonset.yaml
```

### 3. Verify the Installation

Check that the SOCNI pods are running on all nodes:

```bash
kubectl get pods -n kube-system -l app=socni
```

You should see one pod per node in your cluster.

### 4. Test with an Example Pod

Deploy the example pod to test the SOCNI VLAN network:

```bash
kubectl apply -f socni/manifests/socni-example-pod.yaml
```

Verify the pod is running and has the correct network interface:

```bash
kubectl exec -it socni-example -- ip addr
```

You should see a network interface with the VLAN ID specified in the configuration.

## Multi-Tenant Configuration

To set up multi-tenant isolation with different security levels:

1. Create NetworkAttachmentDefinitions for each tenant with appropriate VLAN IDs and security policies:

```bash
kubectl apply -f socni/manifests/socni-multi-tenant-example.yaml
```

2. Deploy pods for each tenant with the appropriate network annotation:

```bash
kubectl apply -f socni/manifests/socni-multi-tenant-example.yaml
```

3. Verify network isolation between tenants:

```bash
# From tenant-a-pod
kubectl exec -it tenant-a-pod -- ping -c 3 <tenant-b-pod-ip>

# From tenant-b-pod
kubectl exec -it tenant-b-pod -- ping -c 3 <tenant-a-pod-ip>
```

Based on the security policies, communication between tenants should be restricted according to the policy configuration.

## Troubleshooting

If you encounter issues:

1. Check the SOCNI pod logs:

```bash
kubectl logs -n kube-system -l app=socni
```

2. Verify the CNI plugin is properly installed:

```bash
kubectl exec -it -n kube-system $(kubectl get pods -n kube-system -l app=socni -o jsonpath='{.items[0].metadata.name}') -- ls -la /opt/cni/bin/vlan
```

3. Check the CNI configuration:

```bash
kubectl exec -it -n kube-system $(kubectl get pods -n kube-system -l app=socni -o jsonpath='{.items[0].metadata.name}') -- cat /etc/cni/net.d/vlan.conf
```

## Advanced Configuration

For more advanced configuration options, refer to the SOCNI documentation and policy examples in the `policy-examples` directory. 