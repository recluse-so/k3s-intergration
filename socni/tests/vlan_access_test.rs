// File: socni/tests/vlan_access_test.rs

use std::collections::HashMap;
use std::path::PathBuf;

// Import from socni crate
use socni::config::NetConf;
use socni::plugin::VlanPlugin;
use socni::types::{CmdArgs, Result as CniResult};
use socni::integrations::aranya::AranyaClient;

// Test structure to simulate tenant and VLAN operations
struct VlanAccessTest {
    aranya_client: AranyaClient,
    // This would be your VLAN manager in a real implementation
    vlans: HashMap<u16, Vec<String>>, // VLAN ID -> List of tenant IDs with access
}

impl VlanAccessTest {
    fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let aranya_client = AranyaClient::new(
            PathBuf::from("/var/run/aranya/api.sock"),
            "admin".to_string()
        )?;
        
        let mut vlans = HashMap::new();
        
        // Add some test VLANs
        vlans.insert(100, vec!["tenant1".to_string()]);
        vlans.insert(200, vec!["tenant1".to_string(), "tenant2".to_string()]);
        
        Ok(Self { aranya_client, vlans })
    }
    
    // Test if a tenant can access a specific VLAN
    fn test_vlan_access(&mut self, tenant_id: &str, vlan_id: u16) -> Result<bool, Box<dyn std::error::Error>> {
        // First check policy using Aranya client
        let has_access = self.aranya_client.check_vlan_access(vlan_id)?;
        
        // If policy allows access, check if VLAN exists and tenant has access
        if has_access {
            if let Some(tenants) = self.vlans.get(&vlan_id) {
                return Ok(tenants.contains(&tenant_id.to_string()));
            }
        }
        
        Ok(false)
    }
    
    // Add a VLAN (admin operation)
    fn add_vlan(&mut self, tenant_id: &str, vlan_id: u16) -> Result<(), Box<dyn std::error::Error>> {
        // Check if tenant can create VLANs using Aranya client
        if self.aranya_client.check_vlan_access(vlan_id)? {
            self.vlans.entry(vlan_id).or_insert_with(|| vec![tenant_id.to_string()]);
            Ok(())
        } else {
            Err("Permission denied: Not an admin".into())
        }
    }
    
    // Grant access to another tenant (admin operation)
    fn grant_access(&mut self, admin_id: &str, target_tenant: &str, vlan_id: u16) 
                  -> Result<(), Box<dyn std::error::Error>> {
        // Check if admin has access using Aranya client
        if self.aranya_client.check_vlan_access(vlan_id)? {
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
    fn test_tenant_vlan_access() -> Result<(), Box<dyn std::error::Error>> {
        let mut test = VlanAccessTest::new()?;
        
        // Test admin access
        assert!(test.test_vlan_access("admin", 100)?);
        assert!(test.test_vlan_access("admin", 200)?);
        assert!(test.test_vlan_access("admin", 300)?); // Admin can access even non-existent VLANs
        
        // Test tenant1 access
        assert!(test.test_vlan_access("tenant1", 100)?);
        assert!(test.test_vlan_access("tenant1", 200)?);
        assert!(!test.test_vlan_access("tenant1", 300)?); // VLAN doesn't exist
        
        // Test tenant2 access
        assert!(!test.test_vlan_access("tenant2", 100)?); // No access to VLAN 100
        assert!(test.test_vlan_access("tenant2", 200)?);
        assert!(!test.test_vlan_access("tenant2", 300)?);
        
        // Test unknown tenant
        assert!(!test.test_vlan_access("unknown", 100)?);
        assert!(!test.test_vlan_access("unknown", 200)?);
        
        Ok(())
    }
    
    #[test]
    fn test_vlan_management() -> Result<(), Box<dyn std::error::Error>> {
        let mut test = VlanAccessTest::new()?;
        
        // Admin can add VLANs
        test.add_vlan("admin", 300)?;
        assert!(test.test_vlan_access("admin", 300)?);
        
        // Tenant1 cannot add VLANs
        assert!(test.add_vlan("tenant1", 400).is_err());
        
        // Admin can grant access
        test.grant_access("admin", "tenant1", 300)?;
        assert!(test.test_vlan_access("tenant1", 300)?);
        
        // Tenant cannot grant access
        assert!(test.grant_access("tenant1", "tenant2", 300).is_err());
        
        Ok(())
    }
}