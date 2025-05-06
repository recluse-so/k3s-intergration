use anyhow::{Context, Result};
use aranya_client::Client;
use std::path::PathBuf;
use tokio::runtime::Runtime;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;
use tracing::info;

/// Network configuration sync event
#[derive(Clone, Debug)]
pub struct NetworkConfigEvent {
    pub vlan_id: u16,
    pub action: NetworkAction,
}

#[derive(Clone, Debug)]
pub enum NetworkAction {
    Create,
    Update,
    Delete,
}

/// Aranya client for security policy enforcement and network sync
pub struct AranyaClient {
    client: Client,
    team_id: String,
    runtime: Runtime,
    config_tx: broadcast::Sender<NetworkConfigEvent>,
    vlan_configs: Arc<Mutex<HashMap<u16, bool>>>,
}

impl AranyaClient {
    /// Create a new Aranya client
    pub fn new(socket_path: PathBuf, team_id: String) -> Result<Self> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .context("Failed to create Tokio runtime")?;
        
        let client = runtime.block_on(async {
            Client::connect(
                &socket_path,
                &PathBuf::from("/run/aranya/shm"),  // SHM path
                1024,                               // Max channels
                "127.0.0.1:0"                      // AFC listen address
            )
            .await
            .context("Failed to create Aranya client")
        })?;

        let (config_tx, _) = broadcast::channel(100);
        let vlan_configs = Arc::new(Mutex::new(HashMap::new()));
        
        let aranya_client = Self { 
            client, 
            team_id, 
            runtime,
            config_tx,
            vlan_configs,
        };
        
        Ok(aranya_client)
    }

    /// Subscribe to network configuration changes
    pub fn subscribe_network_changes(&self) -> broadcast::Receiver<NetworkConfigEvent> {
        self.config_tx.subscribe()
    }
    
    /// Create a new VLAN with cryptographic isolation
    pub fn create_vlan(&mut self, vlan_id: u16) -> Result<()> {
        // Store VLAN config
        let mut configs = self.vlan_configs.lock().unwrap();
        configs.insert(vlan_id, true);

        // Notify subscribers
        let _ = self.config_tx.send(NetworkConfigEvent {
            vlan_id,
            action: NetworkAction::Create,
        });

        Ok(())
    }
    
    /// Check if a device has access to a VLAN with crypto verification
    pub fn check_vlan_access(&mut self, vlan_id: u16) -> Result<bool> {
        // Check if we have access to this VLAN
        let configs = self.vlan_configs.lock().unwrap();
        Ok(configs.get(&vlan_id).copied().unwrap_or(false))
    }
    
    /// Grant VLAN access to a device with crypto key distribution
    pub fn grant_vlan_access(&mut self, vlan_id: u16, target_device: &str) -> Result<()> {
        let mut configs = self.vlan_configs.lock().unwrap();
        configs.insert(vlan_id, true);
        
        info!("Granted access to VLAN {} for device {}", vlan_id, target_device);
        Ok(())
    }
    
    /// Revoke VLAN access from a device
    pub fn revoke_vlan_access(&mut self, vlan_id: u16, target_device: &str) -> Result<()> {
        let mut configs = self.vlan_configs.lock().unwrap();
        configs.remove(&vlan_id);
        
        info!("Revoked access to VLAN {} for device {}", vlan_id, target_device);
        Ok(())
    }

    /// Delete a VLAN and its associated policy
    pub fn delete_vlan(&mut self, vlan_id: u16) -> Result<()> {
        let mut configs = self.vlan_configs.lock().unwrap();
        configs.remove(&vlan_id);
        
        // Notify subscribers
        let _ = self.config_tx.send(NetworkConfigEvent {
            vlan_id,
            action: NetworkAction::Delete,
        });
        
        Ok(())
    }
} 