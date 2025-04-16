// File: socni/tests/vlan_access_test.rs

mod policies;
use policies::vlan_policy::create_test_policy_engine;

use aranya_daemon::policy::Effect;
use socni::config::NetConf;
use std::collections::HashMap;
use std::path::PathBuf;

// Test structure to simulate tenant and VLAN operations
struct VlanAccessTest {
    policy_engine: PolicyEngine<DefaultEngine, Store>,
    // This would be your VLAN manager in a real implementation
    vlans: HashMap<u16, Vec<String>>, // VLAN ID -> List of tenant IDs with access
}

impl VlanAccessTest {
    fn new() -> Self {
        let policy_engine = create_test_policy_engine();
        let mut vlans = HashMap::new();
        
        // Add some test VLANs
        vlans.insert(100, vec!["tenant1".to_string()]);
        vlans.insert(200, vec!["tenant1".to_string(), "tenant2".to_string()]);
        
        Self { policy_engine, vlans }
    }
    
    // Test if a tenant can access a specific VLAN
    fn test_vlan_access(&self, tenant_id: &str, vlan_id: u16) -> bool {
        // First check policy
        let permission = format!("sdwan:access_vlan:{}", vlan_id);
        let policy_result = self.policy_engine.check_permission(
            tenant_id, 
            Permission::Custom(permission)
        ).unwrap_or(Effect::Deny);
        
        // If policy allows access, check if VLAN exists and tenant has access
        if let Effect::Allow = policy_result {
            if let Some(tenants) = self.vlans.get(&vlan_id) {
                return tenants.contains(&tenant_id.to_string()) || 
                       self.is_admin(tenant_id).unwrap_or(false);
            }
        }
        
        false
    }
    
    // Check if tenant has admin access
    fn is_admin(&self, tenant_id: &str) -> Result<bool, Box<dyn std::error::Error>> {
        let result = self.policy_engine.check_permission(
            tenant_id,
            Permission::Custom("sdwan:admin".to_string())
        )?;
        
        Ok(matches!(result, Effect::Allow))
    }
    
    // Add a VLAN (admin operation)
    fn add_vlan(&mut self, tenant_id: &str, vlan_id: u16) -> Result<(), Box<dyn std::error::Error>> {
        // Check if tenant can create VLANs
        if self.is_admin(tenant_id)? {
            self.vlans.entry(vlan_id).or_insert_with(|| vec![tenant_id.to_string()]);
            Ok(())
        } else {
            Err("Permission denied: Not an admin".into())
        }
    }
    
    // Grant access to another tenant (admin operation)
    fn grant_access(&mut self, admin_id: &str, target_tenant: &str, vlan_id: u16) 
                  -> Result<(), Box<dyn std::error::Error>> {
        if self.is_admin(admin_id)? {
            if let Some(tenants) = self.vlans.get_mut(&vlan_id) {
                if !tenants.contains(&target_tenant.to_string()) {
                    tenants.push(target_tenant.to_string());
                }
                Ok(())
            } else {
                Err(format!("VLAN {} does not exist", vlan_id).into())
            }
        } else {
            Err("Permission denied: Not an admin".into())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_tenant_vlan_access() {
        let test = VlanAccessTest::new();
        
        // Test admin access
        assert!(test.test_vlan_access("admin", 100));
        assert!(test.test_vlan_access("admin", 200));
        assert!(test.test_vlan_access("admin", 300)); // Admin can access even non-existent VLANs (policy allows)
        
        // Test tenant1 access
        assert!(test.test_vlan_access("tenant1", 100));
        assert!(test.test_vlan_access("tenant1", 200));
        assert!(!test.test_vlan_access("tenant1", 300)); // VLAN doesn't exist
        
        // Test tenant2 access
        assert!(!test.test_vlan_access("tenant2", 100)); // No access to VLAN 100
        assert!(test.test_vlan_access("tenant2", 200));
        assert!(!test.test_vlan_access("tenant2", 300));
        
        // Test unknown tenant
        assert!(!test.test_vlan_access("unknown", 100));
        assert!(!test.test_vlan_access("unknown", 200));
    }
    
    #[test]
    fn test_vlan_management() -> Result<(), Box<dyn std::error::Error>> {
        let mut test = VlanAccessTest::new();
        
        // Admin can add VLANs
        test.add_vlan("admin", 300)?;
        assert!(test.test_vlan_access("admin", 300));
        
        // Tenant1 cannot add VLANs
        assert!(test.add_vlan("tenant1", 400).is_err());
        
        // Admin can grant access
        test.grant_access("admin", "tenant1", 300)?;
        assert!(test.test_vlan_access("tenant1", 300));
        
        // Tenant cannot grant access
        assert!(test.grant_access("tenant1", "tenant2", 300).is_err());
        
        Ok(())
    }
}