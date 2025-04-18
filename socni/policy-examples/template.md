---
policy-version: 2
---

# Multi-Tenant Policy Template

This policy extends the default Aranya policy to support multi-tenant network isolation and access control.

## Roles & Permissions

The policy maintains the base roles from the default policy while adding tenant-specific roles and permissions:

* Owner:
  * All default Owner permissions
  * Create/terminate Tenant
  * Assign/revoke Tenant roles
  * Define tenant network policies
  * Manage tenant isolation

* Admin:
  * All default Admin permissions
  * Manage tenant network access
  * Define tenant labels
  * Assign tenant roles

* Operator:
  * All default Operator permissions
  * Manage tenant network configurations
  * Assign tenant labels
  * Configure tenant access

* Member:
  * All default Member permissions
  * Access tenant networks based on labels
  * Create/delete tenant channels

**Invariants**:

- Each tenant has its own isolated network space
- Network access between tenants must be explicitly allowed
- Tenant labels control network access within a tenant
- A device can belong to multiple tenants with different roles
- Tenant network policies are enforced at the CNI level

### Imports & Global Constants

```policy
use afc
use aqc
use crypto
use device
use envelope
use idam
use perspective
use tenant
```

### Enums & Structs

```policy
// Extends the base Role enum with tenant roles
enum Role {
    Owner,
    Admin,
    Operator,
    Member,
    TenantOwner,
    TenantAdmin,
    TenantOperator,
    TenantMember,
}

// Tenant network access types
enum NetworkAccess {
    Isolated,
    Shared,
    Restricted,
}

// Tenant security levels
enum SecurityLevel {
    High,
    Medium,
    Low,
}

// Tenant configuration
struct TenantConfig {
    tenant_id id,
    network_id string,
    security_level enum SecurityLevel,
    access_type enum NetworkAccess,
}

// Tenant network policy
struct NetworkPolicy {
    tenant_id id,
    allowed_tenants list<id>,
    security_level enum SecurityLevel,
    access_type enum NetworkAccess,
}
```

### Facts

```policy
// Tenant configuration
fact Tenant[tenant_id id]=>{
    network_id string,
    security_level enum SecurityLevel,
    access_type enum NetworkAccess
}

// Tenant network policy
fact TenantNetworkPolicy[tenant_id id]=>{
    allowed_tenants list<id>,
    security_level enum SecurityLevel,
    access_type enum NetworkAccess
}

// Tenant device role
fact TenantDeviceRole[tenant_id id, device_id id]=>{
    role enum Role
}

// Tenant network label
fact TenantLabel[tenant_id id, label_id id]=>{
    name string,
    security_level enum SecurityLevel
}

// Tenant network access
fact TenantNetworkAccess[tenant_id id, target_tenant_id id]=>{
    access_type enum NetworkAccess
}
```

### Functions

```policy
// Verify tenant exists
function verify_tenant(tenant_id id) struct TenantConfig {
    let tenant = check_unwrap query Tenant[tenant_id: id]
    return TenantConfig {
        tenant_id: id,
        network_id: tenant.network_id,
        security_level: tenant.security_level,
        access_type: tenant.access_type,
    }
}

// Verify tenant device role
function verify_tenant_role(tenant_id id, device_id id) enum Role {
    let role = check_unwrap query TenantDeviceRole[tenant_id: id, device_id: id]
    return role.role
}

// Check network access between tenants
function can_access_tenant_network(source_tenant_id id, target_tenant_id id) bool {
    let source_policy = check_unwrap query TenantNetworkPolicy[tenant_id: source_tenant_id]
    let target_policy = check_unwrap query TenantNetworkPolicy[tenant_id: target_tenant_id]
    
    // Check explicit access
    if list::contains(source_policy.allowed_tenants, target_tenant_id) {
        return true
    }
    
    // Check shared access
    if source_policy.access_type == NetworkAccess::Shared &&
       target_policy.access_type == NetworkAccess::Shared {
        return true
    }
    
    return false
}

// Verify security level compatibility
function verify_security_level(source_level enum SecurityLevel, target_level enum SecurityLevel) bool {
    match source_level {
        SecurityLevel::High => { return true }
        SecurityLevel::Medium => { return target_level != SecurityLevel::High }
        SecurityLevel::Low => { return target_level == SecurityLevel::Low }
    }
}
```

### Commands

```policy
// Create a new tenant
action create_tenant(network_id string, security_level enum SecurityLevel, access_type enum NetworkAccess) {
    publish CreateTenant {
        network_id: network_id,
        security_level: security_level,
        access_type: access_type,
    }
}

effect TenantCreated {
    tenant_id id,
    network_id string,
    security_level enum SecurityLevel,
    access_type enum NetworkAccess,
}

command CreateTenant {
    fields {
        network_id string,
        security_level enum SecurityLevel,
        access_type enum NetworkAccess,
    }

    seal { return seal_command(serialize(this)) }
    open { return deserialize(open_envelope(envelope)) }

    policy {
        let author = get_valid_device(envelope::author_id(envelope))
        check is_owner(author.role)

        let tenant_id = envelope::command_id(envelope)

        finish {
            create Tenant[tenant_id: tenant_id]=>{
                network_id: this.network_id,
                security_level: this.security_level,
                access_type: this.access_type,
            }

            create TenantNetworkPolicy[tenant_id: tenant_id]=>{
                allowed_tenants: [],
                security_level: this.security_level,
                access_type: this.access_type,
            }

            emit TenantCreated {
                tenant_id: tenant_id,
                network_id: this.network_id,
                security_level: this.security_level,
                access_type: this.access_type,
            }
        }
    }
}

// Allow network access between tenants
action allow_tenant_access(source_tenant_id id, target_tenant_id id) {
    publish AllowTenantAccess {
        source_tenant_id: source_tenant_id,
        target_tenant_id: target_tenant_id,
    }
}

effect TenantAccessAllowed {
    source_tenant_id id,
    target_tenant_id id,
}

command AllowTenantAccess {
    fields {
        source_tenant_id id,
        target_tenant_id id,
    }

    seal { return seal_command(serialize(this)) }
    open { return deserialize(open_envelope(envelope)) }

    policy {
        let author = get_valid_device(envelope::author_id(envelope))
        check is_owner(author.role) || is_admin(author.role)

        let source_tenant = verify_tenant(this.source_tenant_id)
        let target_tenant = verify_tenant(this.target_tenant_id)

        // Verify security level compatibility
        check verify_security_level(source_tenant.security_level, target_tenant.security_level)

        finish {
            let current_policy = check_unwrap query TenantNetworkPolicy[tenant_id: this.source_tenant_id]
            let updated_tenants = list::append(current_policy.allowed_tenants, [this.target_tenant_id])

            update TenantNetworkPolicy[tenant_id: this.source_tenant_id]=>{
                allowed_tenants: current_policy.allowed_tenants,
                security_level: current_policy.security_level,
                access_type: current_policy.access_type,
            } to {
                allowed_tenants: updated_tenants,
                security_level: current_policy.security_level,
                access_type: current_policy.access_type,
            }

            emit TenantAccessAllowed {
                source_tenant_id: this.source_tenant_id,
                target_tenant_id: this.target_tenant_id,
            }
        }
    }
}
``` 