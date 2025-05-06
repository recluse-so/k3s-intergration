# Aranya K3s Installation

This directory contains the Kubernetes manifests for installing Aranya in a k3s cluster. The installation is organized using Kustomize for better management of different environments.

## Directory Structure

```
vanilla-install/
├── base/                    # Base configuration
│   ├── 00-namespace.yaml   # Namespace definition
│   ├── 01-storage.yaml     # Storage configuration
│   ├── 02-daemon.yaml      # Aranya daemon DaemonSet
│   ├── 03-network.yaml     # Network policies and services
│   ├── 04-monitoring.yaml  # Monitoring configuration
│   ├── 05-backup.yaml      # Backup configuration
│   ├── 06-restore-job.yaml # Restore job template
│   └── kustomization.yaml  # Base kustomization
└── overlays/               # Environment-specific overlays
    ├── dev/               # Development environment
    │   ├── patches/      # Development-specific patches
    │   └── kustomization.yaml
    └── prod/             # Production environment
        ├── patches/      # Production-specific patches
        └── kustomization.yaml
```

## Prerequisites

1. A running k3s cluster
2. kubectl configured to interact with your cluster
3. kustomize installed
4. Storage class configured in your cluster
5. Monitoring stack (Prometheus, Grafana) for production use

## Installation

### Development Environment

```bash
# Apply the development configuration
kubectl apply -k overlays/dev
```

### Production Environment

```bash
# Apply the production configuration
kubectl apply -k overlays/prod
```

## Verification

After installation, verify the deployment:

```bash
# Check if the daemon is running on all nodes
kubectl get daemonset -n aranya

# Check the daemon pods
kubectl get pods -n aranya

# Check the services
kubectl get svc -n aranya

# Check the persistent volume claims
kubectl get pvc -n aranya

# Check the backup cronjob
kubectl get cronjob -n aranya
```

## Monitoring

The installation includes basic monitoring setup:

- ServiceMonitor for Prometheus integration
- Basic alerting rules
- Resource usage monitoring

## Backup and Restore

The installation includes automated backup of the FactDB:

### Automated Backups

- Daily backups are scheduled via a CronJob
- Backups are stored in a dedicated PVC
- The last 7 backups are retained

### Manual Restore

To restore from a backup:

1. Copy the backup file to the restore job:
```bash
# Get the backup PVC pod
BACKUP_POD=$(kubectl get pods -n aranya -l job-name=aranya-factdb-backup -o jsonpath='{.items[0].metadata.name}')

# Copy the backup file to the restore location
kubectl cp /path/to/backup.tar.gz aranya/$BACKUP_POD:/backup/aranya-factdb-restore.tar.gz
```

2. Run the restore job:
```bash
kubectl apply -f k8s/vanilla-install/base/06-restore-job.yaml
```

3. Monitor the restore progress:
```bash
kubectl logs -n aranya -l job-name=aranya-factdb-restore
```

## Troubleshooting

1. Check daemon logs:
```bash
kubectl logs -n aranya -l app=aranya-daemon
```

2. Check daemon status:
```bash
kubectl describe daemonset -n aranya aranya-daemon
```

3. Check storage status:
```bash
kubectl describe pvc -n aranya aranya-factdb
```

4. Check backup status:
```bash
kubectl get cronjob -n aranya
kubectl get jobs -n aranya
kubectl logs -n aranya -l job-name=aranya-factdb-backup
```


## Deployment Instructions

1. Apply the policy to your Aranya daemon:

```bash
# Create a ConfigMap with the policy
kubectl create configmap aranya-policy --from-file=team-policy.md -n aranya

# Update the Aranya daemon to use the policy
kubectl patch daemonset aranya-daemon -n aranya --patch '{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "aranya-daemon",
            "volumeMounts": [
              {
                "name": "policy-volume",
                "mountPath": "/etc/aranya/policy.md",
                "subPath": "team-policy.md"
              }
            ]
          }
        ],
        "volumes": [
          {
            "name": "policy-volume",
            "configMap": {
              "name": "aranya-policy"
            }
          }
        ]
      }
    }
  }
}'
```

2. Verify the policy is applied:

```bash
# Check if the policy is mounted
kubectl describe pod -n aranya -l app=aranya-daemon | grep -A 5 Mounts
```

## Node Identification

For this policy to work correctly, you need to ensure that each node is properly identified. You can do this by:

1. Adding node labels that match the device names in the policy:

```bash
# Label the control plane node
kubectl label nodes <control-plane-node> aranya-name=k3s-control-plane

# Label the agent nodes
kubectl label nodes <agent-node-1> aranya-name=k3s-agent-1
kubectl label nodes <agent-node-2> aranya-name=k3s-agent-2
# ... and so on for all nodes
```

2. Update the Aranya daemon configuration to use these labels for identification:

```json
{
  "name": "{{ .Node.Labels.aranya-name }}",
  "work_dir": "/var/lib/aranya",
  "uds_api_path": "/var/run/aranya/uds.sock",
  "pid_file": "/var/run/aranya/daemon.pid",
  "sync_addr": "0.0.0.0:4321",
  "afc": {
    "shm_path": "/var/lib/aranya/afc",
    "unlink_on_startup": false,
    "unlink_at_exit": false,
    "create": true,
    "max_chans": 100
  }
}
``` 

## Configuration

The main configuration is stored in the ConfigMap `aranya-config`. You can modify it by:

1. Editing the base configuration in `base/01-storage.yaml`
2. Creating a patch in the overlay's `patches` directory
3. Using the configMapGenerator in the overlay's kustomization.yaml

## Security

The installation includes:

- Network policies for DTLS communication
- Resource limits and requests
- Readiness and liveness probes
- Secure storage configuration

## Maintenance

Regular maintenance tasks:

1. Monitor resource usage
2. Check logs for errors
3. Verify DTLS connections
4. Backup FactDB data
5. Update the daemon image when new versions are available
6. Verify backup integrity periodically
7. Test restore procedures in a non-production environment



