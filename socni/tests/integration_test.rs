// File: socni/tests/integration_test.rs

use socni::config::NetConf;
use socni::plugin::VlanPlugin;
use socni::types::{CmdArgs, Result as CniResult};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use tempfile::TempDir;

// For real testing, you'd need to implement this to talk to Aranya daemon
struct AranyaClient {
    socket_path: PathBuf,
    tenant_id: String,
}

impl AranyaClient {
    fn new(socket_path: PathBuf, tenant_id: String) -> Self {
        Self { socket_path, tenant_id }
    }
    
    fn check_vlan_access(&self, vlan_id: u16) -> bool {
        // In a real implementation, this would call Aranya daemon
        // For testing, we'll simulate based on the tenant ID
        match self.tenant_id.as_str() {
            "admin" => true,
            "tenant1" => vlan_id == 100 || vlan_id == 200,
            "tenant2" => vlan_id == 200,
            _ => false,
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
    
    // This test requires root privileges to run
    #[test]
    #[ignore]
    fn test_vlan_cni_with_aranya() -> Result<(), Box<dyn std::error::Error>> {
        // Skip if not running as root
        if !nix::unistd::geteuid().is_root() {
            println!("Skipping test_vlan_cni_with_aranya: not running as root");
            return Ok(());
        }
        
        // Create Aranya client for admin
        let aranya = AranyaClient::new(
            PathBuf::from("/tmp/aranya.sock"), 
            "admin".to_string()
        );
        
        // Create test netns
        let netns_name = "test_vlan_netns";
        create_test_netns(netns_name)?;
        let netns_path = format!("/var/run/netns/{}", netns_name);
        
        // Create VLAN config
        let vlan_id = 100;
        let master = "eth0"; // Change to a real interface on your system
        
        // Check access using Aranya policy
        if !aranya.check_vlan_access(vlan_id) {
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
            netns: netns_path,
            ifname: "eth1".to_string(),
            args: HashMap::new(),
            path: "/opt/cni/bin".to_string(),
            stdin_data: serde_json::to_vec(&conf)?,
        };
        
        // Create VLAN plugin
        let plugin = VlanPlugin::new(conf, args);
        
        // Add network
        let result = plugin.add_network()?;
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
        
        let plugin = VlanPlugin::new(conf, args);
        plugin.del_network()?;
        
        // Clean up
        delete_test_netns(netns_name)?;
        
        Ok(())
    }
}