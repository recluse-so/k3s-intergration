# Understanding the SOCNI Policy Template

The `template.md` file contains a policy definition written in Aranya's policy language, which is used to define security and access control rules for the SOCNI (Secure VLAN CNI) plugin. Let me explain the key concepts and components:

## What is a Fact?

In the context of the Aranya policy language, a **fact** is a persistent data structure that represents a truth or state in the system. Facts are used to store and query information about the system's state, such as:

- Tenant configurations
- Network policies
- Device roles
- Security labels

Facts are defined with a specific syntax that includes:

- A name (e.g., `Tenant`, `TenantNetworkPolicy`)
- Key fields in square brackets (e.g., `[tenant_id id]`)
- Value fields in curly braces (e.g., `=>{ network_id string, ... }`)

For example, this fact:

```policy
fact Tenant[tenant_id id]=>{
    network_id string,
    security_level enum SecurityLevel,
    access_type enum NetworkAccess
}
```

Defines a fact named `Tenant` that:

- Is indexed by a `tenant_id` field
- Contains three fields: `network_id`, `security_level`, and `access_type`
- Can be queried using the `query Tenant[tenant_id: id]` syntax

## Key Components of the Policy Template

### 1. Roles & Permissions

The policy defines a hierarchical role system:

- **Owner**: Has full control, including tenant management
- **Admin**: Can manage tenant network access and labels
- **Operator**: Can configure tenant networks and assign labels
- **Member**: Can access tenant networks based on labels

Each role has specific permissions related to tenant management and network access.

### 2. Enums & Structs

The policy defines several custom types:

- **Role**: Extends the base roles with tenant-specific roles
- **NetworkAccess**: Defines how tenants can access networks (Isolated, Shared, Restricted)
- **SecurityLevel**: Defines security levels (High, Medium, Low)
- **TenantConfig**: Combines tenant configuration parameters
- **NetworkPolicy**: Defines network access policies

### 3. Facts

As explained above, facts store persistent data about:

- Tenant configurations
- Network policies
- Device roles within tenants
- Network labels
- Network access permissions

### 4. Functions

The policy includes functions to:

- Verify tenant existence
- Check tenant device roles
- Determine network access between tenants
- Verify security level compatibility

### 5. Commands

Commands define actions that can be performed:

- **CreateTenant**: Creates a new tenant with specific configuration
- **AllowTenantAccess**: Grants network access between tenants

Each command includes:

- Fields that define the command parameters
- Policy rules that determine who can execute the command
- Effects that describe what happens when the command is executed

## How This Policy Works in Practice

1. **Tenant Creation**:
   - An Owner creates a new tenant with a specific security level and access type
   - The system creates a Tenant fact and a TenantNetworkPolicy fact
   - The tenant is isolated by default

2. **Network Access Control**:
   - An Owner or Admin can allow access between tenants
   - The system verifies security level compatibility
   - If allowed, the target tenant is added to the allowed_tenants list

3. **Policy Enforcement**:
   - When a pod tries to communicate with another pod
   - The CNI plugin checks the tenant policies
   - Communication is allowed or denied based on the policies

## Practical Example

Let's say you have two tenants:

1. **Tenant A** (High security, Isolated access)
2. **Tenant B** (Medium security, Restricted access)

By default, pods in Tenant A cannot communicate with pods in Tenant B because:

- Tenant A has a higher security level
- Both tenants have restricted access types

If an Admin wants to allow communication:

1. They execute the `AllowTenantAccess` command
2. The system verifies security level compatibility
3. Tenant B is added to Tenant A's allowed_tenants list
4. Pods in Tenant A can now communicate with pods in Tenant B

This policy language provides a powerful way to define and enforce network isolation and access control in a multi-tenant Kubernetes environment, ensuring that security boundaries are maintained according to the defined rules.

### Configuration Flow For This CNI

   Pod Creation
   ↓
   Pod Annotations
   ↓
   Aranya Policy Engine
   ↓
   SOCNI Plugin
   ↓
   Network Interface Creation
