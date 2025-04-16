use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::fs;

/// Configuration for SOCNI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SocniConfig {
    /// Path to the CNI bin directory
    pub cni_bin_dir: PathBuf,
    /// Path to the CNI config directory
    pub cni_conf_dir: PathBuf,
    /// Path to store VLAN state
    pub state_dir: PathBuf,
    /// Default bridge interface name
    pub default_master: String,
    /// Default MTU for VLAN interfaces
    pub default_mtu: Option<u32>,
}

impl Default for SocniConfig {
    fn default() -> Self {
        Self {
            cni_bin_dir: PathBuf::from("/opt/cni/bin"),
            cni_conf_dir: PathBuf::from("/etc/cni/net.d"),
            state_dir: PathBuf::from("/var/lib/vlan-cni"),
            default_master: "eth0".to_string(),
            default_mtu: None,
        }
    }
}

/// Network configuration for the VLAN CNI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetConf {
    /// CNI specification version
    #[serde(rename = "cniVersion")]
    pub cni_version: String,
    /// Name of the network
    pub name: String,
    /// Type of CNI plugin
    #[serde(rename = "type")]
    pub plugin_type: String,
    /// Master interface to attach VLAN to
    pub master: String,
    /// VLAN ID (1-4094)
    pub vlan: u16,
    /// Interface MTU
    pub mtu: Option<u32>,
    /// IPAM configuration
    pub ipam: Option<IPAMConfig>,
}

/// IPAM (IP Address Management) configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IPAMConfig {
    /// Type of IPAM plugin
    #[serde(rename = "type")]
    pub ipam_type: String,
    /// Subnet CIDR
    pub subnet: Option<String>,
    /// Range of IPs
    pub range: Option<String>,
    /// Gateway IP
    pub gateway: Option<String>,
    /// Routes
    pub routes: Option<Vec<Route>>,
}

/// Route configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Route {
    /// Destination CIDR
    pub dst: String,
    /// Gateway for this route
    pub gw: Option<String>,
}

impl NetConf {
    /// Parse NetConf from bytes
    pub fn parse(bytes: &[u8]) -> Result<Self> {
        let conf: NetConf = serde_json::from_slice(bytes)
            .context("Failed to parse network configuration")?;
        
        // Validation
        if conf.vlan < 1 || conf.vlan > 4094 {
            anyhow::bail!("Invalid VLAN ID {} (must be between 1 and 4094)", conf.vlan);
        }
        
        if conf.master.is_empty() {
            anyhow::bail!("Master interface name is required");
        }
        
        Ok(conf)
    }
    
    /// Create a default configuration for a VLAN
    pub fn new_default(name: &str, master: &str, vlan: u16, mtu: Option<u32>) -> Self {
        Self {
            cni_version: "1.0.0".to_string(),
            name: name.to_string(),
            plugin_type: "vlan".to_string(),
            master: master.to_string(),
            vlan,
            mtu,
            ipam: None,
        }
    }
    
    /// Save configuration to a file
    pub fn save(&self, path: PathBuf) -> Result<()> {
        let json = serde_json::to_string_pretty(self)?;
        fs::write(path, json)?;
        Ok(())
    }
}

/// Installer for the VLAN CNI plugin
pub struct Installer {
    config: SocniConfig,
}

impl Installer {
    /// Create a new installer
    pub fn new(config: SocniConfig) -> Self {
        Self { config }
    }
    
    /// Install the CNI plugin
    pub fn install(&self) -> Result<()> {
        // Create directories
        for dir in [&self.config.cni_bin_dir, &self.config.cni_conf_dir, &self.config.state_dir] {
            std::fs::create_dir_all(dir)
                .with_context(|| format!("Failed to create directory: {}", dir.display()))?;
        }
        
        // Copy binary to CNI directory
        // In a real implementation, this would be handled by a build script or installation script
        
        // Create default configuration
        let config_path = self.config.cni_conf_dir.join("10-vlan.conflist");
        let config = r#"{
  "cniVersion": "1.0.0",
  "name": "vlan-cni",
  "plugins": [
    {
      "type": "vlan",
      "master": "eth0",
      "vlan": 100,
      "ipam": {
        "type": "host-local",
        "subnet": "10.10.0.0/24"
      }
    }
  ]
}"#;
        
        fs::write(&config_path, config)
            .with_context(|| format!("Failed to write CNI config to {}", config_path.display()))?;
        
        Ok(())
    }
}