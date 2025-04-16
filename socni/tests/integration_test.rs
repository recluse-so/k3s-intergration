// File: socni/tests/integration_test.rs

use std::collections::HashMap;
use std::path::PathBuf;

// Import from the crate directly
use socni::config::NetConf;
use socni::plugin::VlanPlugin;
use socni::types::CmdArgs;
use socni::integrations::aranya::AranyaClient;

// Mock AranyaClient for testing
#[cfg(test)]
mod mock {
    use std::path::PathBuf;
    use anyhow::Result;
    
    pub struct MockAranyaClient {
        tenant_id: String,
    }
    
    impl MockAranyaClient {
        pub fn new(_socket_path: PathBuf, tenant_id: String) -> Result<Self> {
            Ok(Self { tenant_id })
        }
        
        pub fn check_vlan_access(&mut self, vlan_id: u16) -> Result<bool> {
            // For testing, we'll simulate based on the tenant ID
            let access = match self.tenant_id.as_str() {
                "admin" => true,
                "tenant1" => vlan_id == 100 || vlan_id == 200,
                "tenant2" => vlan_id == 200,
                _ => false,
            };
            Ok(access)
        }
        
        #[allow(dead_code)]
        pub fn grant_vlan_access(&mut self, _vlan_id: u16, _target_device: &str) -> Result<()> {
            // Mock implementation
            Ok(())
        }
        
        #[allow(dead_code)]
        pub fn revoke_vlan_access(&mut self, _vlan_id: u16, _target_device: &str) -> Result<()> {
            // Mock implementation
            Ok(())
        }
    }
}

// Function to create a test netns
fn create_test_netns(name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let _ = std::process::Command::new("ip")
        .args(&["netns", "delete", name])
        .output();
    
    let output = std::process::Command::new("ip")
        .args(&["netns", "add", name])
        .output()?;
    
    if !output.status.success() {
        return Err(format!("Failed to create netns: {}", 
                        String::from_utf8_lossy(&output.stderr)).into());
    }
    
    Ok(())
}

// Function to delete a test netns
fn delete_test_netns(name: &str) -> Result<(), Box<dyn std::error::Error>> {
    let output = std::process::Command::new("ip")
        .args(&["netns", "delete", name])
        .output()?;
    
    if !output.status.success() {
        return Err(format!("Failed to delete netns: {}", 
                        String::from_utf8_lossy(&output.stderr)).into());
    }
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::mock::MockAranyaClient;
    
    // Test with mock AranyaClient
    #[test]
    fn test_vlan_cni_with_mock() -> Result<(), Box<dyn std::error::Error>> {
        // Skip if not running as root
        if !nix::unistd::geteuid().is_root() {
            println!("Skipping test_vlan_cni_with_mock: not running as root");
            return Ok(());
        }
        
        // Create mock Aranya client
        let mut aranya = MockAranyaClient::new(
            PathBuf::from("/var/run/aranya/api.sock"), 
            "admin".to_string()
        )?;
        
        // Create test netns
        let netns_name = "test_vlan_netns";
        create_test_netns(netns_name)?;
        let netns_path = format!("/var/run/netns/{}", netns_name);
        
        // Create VLAN config
        let vlan_id = 100;
        let master = "eth0"; // Change to a real interface on your system
        
        // Check access using mock Aranya policy
        if !aranya.check_vlan_access(vlan_id)? {
            delete_test_netns(netns_name)?;
            return Err("Access denied by Aranya policy".into());
        }
        
        // Create CNI config
        let conf = NetConf {
            cni_version: "1.0.0".to_string(),
            name: "test-vlan".to_string(),
            plugin_type: "vlan".to_string(),
            master: master.to_string(),
            vlan: vlan_id,
            mtu: Some(1500),
            ipam: None,
        };
        
        // Create CNI args
        let args = CmdArgs {
            container_id: "test-container".to_string(),
            netns: netns_path.clone(),
            ifname: "eth1".to_string(),
            args: HashMap::new(),
            path: "/opt/cni/bin".to_string(),
            stdin_data: serde_json::to_vec(&conf)?,
        };
        
        // Create VLAN plugin
        let mut plugin = VlanPlugin::new(conf.clone(), args);
        
        // Add network
        let result = tokio::runtime::Runtime::new()?.block_on(plugin.add_network())?;
        println!("CNI result: {:?}", result);
        
        // Now delete the network
        let args = CmdArgs {
            container_id: "test-container".to_string(),
            netns: netns_path,
            ifname: "eth1".to_string(),
            args: HashMap::new(),
            path: "/opt/cni/bin".to_string(),
            stdin_data: serde_json::to_vec(&conf)?,
        };
        
        let mut plugin = VlanPlugin::new(conf, args);
        tokio::runtime::Runtime::new()?.block_on(plugin.del_network())?;
        
        // Clean up
        delete_test_netns(netns_name)?;
        
        Ok(())
    }
    
    // This test requires root privileges and Aranya daemon to run
    #[test]
    #[ignore]
    fn test_vlan_cni_with_real_aranya() -> Result<(), Box<dyn std::error::Error>> {
        // Skip if not running as root
        if !nix::unistd::geteuid().is_root() {
            println!("Skipping test_vlan_cni_with_real_aranya: not running as root");
            return Ok(());
        }
        
        // Create real Aranya client
        let mut aranya = AranyaClient::new(
            PathBuf::from("/var/run/aranya/api.sock"), 
            "admin".to_string()
        )?;
        
        // Create test netns
        let netns_name = "test_vlan_netns_real";
        create_test_netns(netns_name)?;
        let netns_path = format!("/var/run/netns/{}", netns_name);
        
        // Create VLAN config
        let vlan_id = 100;
        let master = "eth0"; // Change to a real interface on your system
        
        // Check access using real Aranya policy
        if !aranya.check_vlan_access(vlan_id)? {
            delete_test_netns(netns_name)?;
            return Err("Access denied by Aranya policy".into());
        }
        
        // Create CNI config
        let conf = NetConf {
            cni_version: "1.0.0".to_string(),
            name: "test-vlan".to_string(),
            plugin_type: "vlan".to_string(),
            master: master.to_string(),
            vlan: vlan_id,
            mtu: Some(1500),
            ipam: None,
        };
        
        // Create CNI args
        let args = CmdArgs {
            container_id: "test-container".to_string(),
            netns: netns_path.clone(),
            ifname: "eth1".to_string(),
            args: HashMap::new(),
            path: "/opt/cni/bin".to_string(),
            stdin_data: serde_json::to_vec(&conf)?,
        };
        
        // Create VLAN plugin
        let mut plugin = VlanPlugin::new(conf.clone(), args);
        
        // Add network
        let result = tokio::runtime::Runtime::new()?.block_on(plugin.add_network())?;
        println!("CNI result: {:?}", result);
        
        // Now delete the network
        let args = CmdArgs {
            container_id: "test-container".to_string(),
            netns: netns_path,
            ifname: "eth1".to_string(),
            args: HashMap::new(),
            path: "/opt/cni/bin".to_string(),
            stdin_data: serde_json::to_vec(&conf)?,
        };
        
        let mut plugin = VlanPlugin::new(conf, args);
        tokio::runtime::Runtime::new()?.block_on(plugin.del_network())?;
        
        // Clean up
        delete_test_netns(netns_name)?;
        
        Ok(())
    }
}