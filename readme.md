# 🛡️ Aranya: Secure Overlay CNI for Kubernetes

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.20%2B-blue)](https://kubernetes.io)
[![CNI](https://img.shields.io/badge/CNI-1.0.0-blue)](https://github.com/containernetworking/cni)

## 📖 Overview

Aranya is a revolutionary micro-segmentation solution built on a zero-trust framework that enables applications to maintain operational capability in contested network environments while ensuring data security and service availability. By reducing complexity in integrating security at the application design level, Aranya provides enterprise best-in-class protection against network threats.

### 🌟 Key Features

- 🔒 End-to-end encryption for all network communications
- 🔐 Device-level authentication
- 📝 Domain-specific policy language for security controls
- 🛡️ Granular access control at the application layer
- 🔄 Automated security policy enforcement
- 🚀 High availability during network attacks
- ⚡ Quick security policy updates without disruption

## 🏗️ Architecture

### Core Components

1. **VLAN CNI Plugin**
   - Implements standard CNI plugin interface (ADD, DEL, CHECK operations)
   - Handles both wired and wireless (WLAN) host interfaces
   - Provides VLAN networking capabilities

2. **Policy Engine**
   - Cryptographic policy enforcement
   - Zero-trust access control
   - Multi-tenant isolation

3. **Network Management**
   - Physical network isolation through VLANs
   - Microsegmentation with fine-grained controls
   - Cross-team collaboration support

## 🚀 Installation

### Prerequisites

- Kubernetes cluster (1.20+)
- Multus CNI plugin
- kubectl configured

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/aranya.git
   cd aranya
   ```

2. Install the CNI plugin:
   ```bash
   ./k8s/minikube-install/install-cni.sh
   ```

3. Verify installation:
   ```bash
   ./k8s/minikube-install/test-cni/scripts/test-socni.sh
   ```

## 🧪 Testing

The project includes comprehensive testing capabilities:

### Test Scripts

- `test-socni.sh`: Tests the SOCNI CNI plugin installation and functionality
- `cleanup-socni.sh`: Cleans up test resources

### Test Coverage

- CNI plugin functionality
- Policy enforcement
- Network isolation
- Multi-tenant scenarios
- Performance metrics

## 📁 Project Structure

```
aranya/
├── k8s/
│   └── minikube-install/
│       ├── install-cni.sh
│       └── test-cni/
│           ├── manifests/
│           │   ├── plugin-install/
│           │   │   ├── socni-daemonset.yaml
│           │   │   ├── socni-rbac.yaml
│           │   │   └── socni-configmap.yaml
│           │   ├── policy/
│           │   │   ├── multi-tenant-policy.md
│           │   │   └── socni-policy-rbac.yaml
│           │   └── network-attachment-definitions/
│           └── scripts/
│               ├── test-socni.sh
│               └── cleanup-socni.sh
└── README.md
```

## 🔄 Comparison with Other Solutions

### vs Service Mesh

| Feature | Aranya | Service Mesh |
|---------|--------|--------------|
| Network Isolation | Physical (VLAN) | Logical (overlay) |
| Performance Impact | Minimal | Moderate |
| Complexity | Low | High |
| Policy Enforcement | Cryptographic | RBAC-based |
| Resource Usage | Light | Heavy |

### vs Traditional CNI

| Feature | Aranya | Traditional CNI |
|---------|--------|----------------|
| Security | Zero-trust | Basic |
| Policy Management | Advanced | Basic |
| Multi-tenant Support | Built-in | Limited |
| Wireless Support | Yes | Limited |
| Audit Capabilities | Comprehensive | Basic |

## 🔒 Security Features

1. **Zero-Trust Architecture**
   - Every connection is verified
   - No implicit trust
   - Continuous validation

2. **Cryptographic Policy Enforcement**
   - Mathematically verifiable policies
   - Tamper-proof enforcement
   - Audit trail

3. **Physical Network Isolation**
   - VLAN-based segmentation
   - Hardware-level security
   - No cross-tenant traffic

## 🎯 Use Cases

1. **Multi-tenant Environments**
   - Complete tenant isolation
   - Secure shared infrastructure
   - Policy-based access control

2. **Regulated Industries**
   - Compliance with strict requirements
   - Audit-ready security controls
   - Data isolation guarantees

3. **Edge Computing**
   - Wireless network support
   - Lightweight implementation
   - Quick policy updates

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Kubernetes community
- CNI project
- All contributors

---

For more information, please visit our [documentation](docs/) or [open an issue](https://github.com/your-org/aranya/issues).
