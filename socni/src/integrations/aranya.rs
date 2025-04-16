use anyhow::{Context, Result};
use aranya_client::Client;
use aranya_daemon_api::{
    ChanOp,
    Role,
    DeviceId as DaemonDeviceId,
};
use aranya_crypto::{
    DeviceId as CryptoDeviceId,
    id::Id,
};
use std::path::PathBuf;
use tokio::runtime::Runtime;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast;

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

/// VLAN access configuration with crypto
#[derive(Clone, Debug)]
struct VlanConfig {
    label_id: String,
    admin_role: Role,
    device_id: CryptoDeviceId,
}

/// Aranya client for security policy enforcement and network sync
pub struct AranyaClient {
    client: Client,
    team_id: String,
    runtime: Runtime,
    config_tx: broadcast::Sender<NetworkConfigEvent>,
    vlan_configs: Arc<Mutex<HashMap<u16, VlanConfig>>>,
}

impl AranyaClient {
    /// Create a new Aranya client
    pub fn new(socket_path: PathBuf, team_id: String) -> Result<Self> {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .context("Failed to create Tokio runtime")?;
        
        let client = runtime.block_on(async {
            Client::connect(&socket_path)
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

    /// Convert from daemon API DeviceId to crypto DeviceId
    fn convert_device_id(device_id: &DaemonDeviceId) -> Result<CryptoDeviceId> {
        // The device ID is a UUID string, we need to parse it into bytes
        let uuid = uuid::Uuid::parse_str(device_id.to_string().as_str())
            .context("Failed to parse device ID as UUID")?;
        
        // Create a new Id from the UUID bytes
        // We need to convert the 16-byte UUID to a 64-byte array
        let mut id_bytes = [0u8; 64];
        id_bytes[..16].copy_from_slice(uuid.as_bytes());
        
        // Create the Id from the bytes
        // Id::from_bytes returns an Id directly, not a Result
        let id = Id::from_bytes(id_bytes);
        
        // Convert Id to CryptoDeviceId
        Ok(CryptoDeviceId::from(id))
    }

    /// Subscribe to network configuration changes
    pub fn subscribe_network_changes(&self) -> broadcast::Receiver<NetworkConfigEvent> {
        self.config_tx.subscribe()
    }
    
    /// Create a new VLAN with cryptographic isolation
    pub fn create_vlan(&mut self, vlan_id: u16) -> Result<()> {
        let label_id = format!("vlan-{}", vlan_id);
        
        self.runtime.block_on(async {
            let team_id = self.team_id.parse()?;
            let mut team = self.client.team(team_id);
            
            // Create VLAN label if it doesn't exist
            team.create_label(label_id.clone()).await?;

            // Get device ID for crypto operations
            let device_id = self.client.get_device_id().await?;
            
            // Convert device ID using the new conversion function
            let crypto_device_id = Self::convert_device_id(&device_id)?;

            // Store VLAN config
            let config = VlanConfig {
                label_id: label_id.clone(),
                admin_role: Role::Admin,
                device_id: crypto_device_id,
            };
            
            let mut configs = self.vlan_configs.lock().unwrap();
            configs.insert(vlan_id, config);

            // Notify subscribers
            let _ = self.config_tx.send(NetworkConfigEvent {
                vlan_id,
                action: NetworkAction::Create,
            });

            Ok(())
        })
    }
    
    /// Check if a device has access to a VLAN with crypto verification
    pub fn check_vlan_access(&mut self, vlan_id: u16) -> Result<bool> {
        let label_id = format!("vlan-{}", vlan_id);
        
        self.runtime.block_on(async {
            let team_id = self.team_id.parse()?;
            
            // First check if the label exists
            let client_clone = &mut self.client;
            let mut queries = client_clone.queries(team_id);
            if !queries.label_exists(label_id.parse()?).await? {
                return Ok(false);
            }
            
            // Get device ID from the client
            let device_id = client_clone.get_device_id().await?;
            
            // Get device role and labels using the same queries instance
            let mut queries = client_clone.queries(team_id);
            let device_role = queries.device_role(device_id).await?;
            let labels = queries.device_label_assignments(device_id).await?;
            
            // Check if device has the VLAN label
            let has_label = labels.iter().any(|l| l.id.to_string() == label_id);

            // Device has access if:
            // 1. They have the VLAN label OR
            // 2. They are an Owner/Admin (who implicitly have access to all VLANs)
            Ok(has_label || matches!(device_role, Role::Owner | Role::Admin))
        })
    }
    
    /// Grant VLAN access to a device with crypto key distribution
    pub fn grant_vlan_access(&mut self, vlan_id: u16, target_device: &str) -> Result<()> {
        let label_id = format!("vlan-{}", vlan_id);
        
        self.runtime.block_on(async {
            let team_id = self.team_id.parse()?;
            
            // Check if label exists
            {
                let client_ref = &mut self.client;
                let mut queries = client_ref.queries(team_id);
                
                if !queries.label_exists(label_id.parse()?).await? {
                    // Create label if it doesn't exist
                    let mut team = self.client.team(team_id);
                    team.create_label(label_id.clone()).await?;
                }
            }
            
            // Assign label to device with read/write permissions
            let mut team = self.client.team(team_id);
            team.assign_label(
                target_device.parse()?,
                label_id.parse()?,
                ChanOp::SendRecv,
            ).await?;
            
            Ok(())
        })
    }
    
    /// Revoke VLAN access from a device
    pub fn revoke_vlan_access(&mut self, vlan_id: u16, target_device: &str) -> Result<()> {
        let label_id = format!("vlan-{}", vlan_id);
        
        self.runtime.block_on(async {
            let team_id = self.team_id.parse()?;
            let mut team = self.client.team(team_id);
            
            // Revoke label from device
            team.revoke_label(
                target_device.parse()?,
                label_id.parse()?
            ).await?;
            
            Ok(())
        })
    }

    /// Delete a VLAN and its associated policy
    pub fn delete_vlan(&mut self, vlan_id: u16) -> Result<()> {
        let configs = self.vlan_configs.lock().unwrap();
        if let Some(config) = configs.get(&vlan_id) {
            let label_id = config.label_id.clone();
            drop(configs); // Release lock before async block
            
            self.runtime.block_on(async {
                let team_id = self.team_id.parse()?;
                let mut team = self.client.team(team_id);
                
                // Delete the VLAN label
                team.delete_label(label_id.parse()?).await?;
                
                // Remove from local config
                let mut configs = self.vlan_configs.lock().unwrap();
                configs.remove(&vlan_id);
                
                // Notify subscribers
                let _ = self.config_tx.send(NetworkConfigEvent {
                    vlan_id,
                    action: NetworkAction::Delete,
                });
                
                Ok(())
            })
        } else {
            Ok(()) // VLAN doesn't exist, nothing to do
        }
    }
} 