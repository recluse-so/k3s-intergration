use anyhow::{Context, Result};
use clap::{Parser, Subcommand, builder::TypedValueParser};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::{info, warn, error};
use tracing_subscriber::{FmtSubscriber, EnvFilter};

// Import our local AranyaClient
mod aranya;
use aranya::AranyaClient;

/// A command line tool to manage VLANs using Aranya security
#[derive(Parser)]
#[command(name = "socni-ctl", author, version, about)]
struct Cli {
    /// Path to Aranya daemon socket
    #[arg(long, default_value = "/var/run/aranya/api.sock")]
    socket: PathBuf,

    /// Tenant ID to use for operations
    #[arg(long)]
    tenant_id: Option<String>,

    /// Path to config directory
    #[arg(long, default_value = "/etc/cni/net.d")]
    config_dir: PathBuf,

    /// Enable verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Subcommand to execute
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new VLAN
    Create {
        /// VLAN ID (1-4094)
        #[arg(long)]
        id: u16,

        /// Master interface
        #[arg(long)]
        master: Option<String>,

        /// Interface MTU
        #[arg(long)]
        mtu: Option<u32>,

        /// Security labels (key=value)
        #[arg(long, value_parser = parse_key_val)]
        label: Vec<(String, String)>,
    },

    /// List available VLANs
    List {
        /// Show detailed information
        #[arg(long)]
        detailed: bool,
    },

    /// Grant VLAN access to a tenant
    Grant {
        /// VLAN ID to grant access to
        #[arg(long)]
        vlan_id: u16,

        /// Target tenant ID to grant access to
        #[arg(long)]
        target_tenant: String,
    },

    /// Revoke VLAN access from a tenant
    Revoke {
        /// VLAN ID to revoke access from
        #[arg(long)]
        vlan_id: u16,

        /// Target tenant ID to revoke access from
        #[arg(long)]
        target_tenant: String,
    },

    /// Generate a VLAN configuration
    Generate {
        /// VLAN ID (1-4094)
        #[arg(long)]
        id: u16,

        /// Master interface
        #[arg(long)]
        master: String,

        /// Interface MTU
        #[arg(long)]
        mtu: Option<u32>,

        /// Network name
        #[arg(long, default_value = "vlan-network")]
        name: String,

        /// Output file path
        #[arg(long)]
        output: Option<PathBuf>,

        /// IPAM subnet (CIDR notation)
        #[arg(long)]
        subnet: Option<String>,

        /// IPAM gateway
        #[arg(long)]
        gateway: Option<String>,
    },

    /// Install the VLAN CNI plugin
    Install {
        /// Skip confirmation
        #[arg(long)]
        yes: bool,

        /// Installation directory
        #[arg(long, default_value = "/opt/cni/bin")]
        bin_dir: PathBuf,
    },

    /// Status of VLAN interfaces
    Status {
        /// VLAN ID to check
        #[arg(long)]
        id: Option<u16>,
    },
}

fn parse_key_val(s: &str) -> Result<(String, String), String> {
    let parts: Vec<&str> = s.splitn(2, '=').collect();
    if parts.len() != 2 {
        return Err(format!("Invalid key=value format: {}", s));
    }
    Ok((parts[0].to_string(), parts[1].to_string()))
}

#[derive(Debug, Serialize, Deserialize)]
struct VlanConfig {
    id: u16,
    master: String,
    mtu: Option<u32>,
    tenant_ids: Vec<String>,
    labels: HashMap<String, String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct VlanStatus {
    id: u16,
    name: String,
    state: String,
    master: String,
    tenants: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct NetworkConfig {
    #[serde(rename = "cniVersion")]
    cni_version: String,
    name: String,
    plugins: Vec<PluginConfig>,
}

#[derive(Debug, Serialize, Deserialize)]
struct PluginConfig {
    #[serde(rename = "type")]
    plugin_type: String,
    master: String,
    vlan: u16,
    mtu: Option<u32>,
    ipam: Option<IpamConfig>,
}

#[derive(Debug, Serialize, Deserialize)]
struct IpamConfig {
    #[serde(rename = "type")]
    ipam_type: String,
    subnet: Option<String>,
    gateway: Option<String>,
}

fn generate_network_config(
    id: u16,
    master: &str,
    mtu: Option<u32>,
    name: &str,
    subnet: Option<&str>,
    gateway: Option<&str>,
) -> NetworkConfig {
    let mut ipam = None;
    if let Some(subnet_str) = subnet {
        ipam = Some(IpamConfig {
            ipam_type: "host-local".to_string(),
            subnet: Some(subnet_str.to_string()),
            gateway: gateway.map(|s| s.to_string()),
        });
    }

    NetworkConfig {
        cni_version: "1.0.0".to_string(),
        name: name.to_string(),
        plugins: vec![PluginConfig {
            plugin_type: "vlan".to_string(),
            master: master.to_string(),
            vlan: id,
            mtu,
            ipam,
        }],
    }
}

fn get_vlan_status(id: Option<u16>) -> Result<Vec<VlanStatus>> {
    let output = Command::new("ip")
        .args(&["-j", "link", "show"])
        .output()
        .context("Failed to execute ip link show command")?;

    if !output.status.success() {
        anyhow::bail!(
            "Failed to get interface status: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let interfaces: Vec<serde_json::Value> = serde_json::from_slice(&output.stdout)
        .context("Failed to parse ip link output")?;

    let mut vlan_status = Vec::new();
    for iface in interfaces {
        // Check if this is a VLAN interface
        if let Some(link_info) = iface.get("linkinfo") {
            if let Some(info_kind) = link_info.get("info_kind") {
                if info_kind.as_str() == Some("vlan") {
                    if let (Some(ifname), Some(iface_id), Some(state), Some(master)) = (
                        iface.get("ifname").and_then(|v| v.as_str()),
                        link_info
                            .get("info_data")
                            .and_then(|d| d.get("id"))
                            .and_then(|v| v.as_u64()),
                        iface.get("operstate").and_then(|v| v.as_str()),
                        iface.get("master").and_then(|v| v.as_str()),
                    ) {
                        let vlan_id = iface_id as u16;
                        
                        // If specific ID was requested, filter for it
                        if let Some(requested_id) = id {
                            if vlan_id != requested_id {
                                continue;
                            }
                        }
                        
                        vlan_status.push(VlanStatus {
                            id: vlan_id,
                            name: ifname.to_string(),
                            state: state.to_string(),
                            master: master.to_string(),
                            tenants: Vec::new(), // We don't have this info from ip command
                        });
                    }
                }
            }
        }
    }

    Ok(vlan_status)
}

async fn run_install(bin_dir: &Path, yes: bool) -> Result<()> {
    // Check if we have the necessary permissions
    if !yes {
        println!("This will install the VLAN CNI plugin to {}.", bin_dir.display());
        println!("You may need root privileges to complete this operation.");
        println!("Continue? [y/N]");
        
        let mut input = String::new();
        std::io::stdin().read_line(&mut input)?;
        
        if !input.trim().eq_ignore_ascii_case("y") {
            println!("Installation aborted.");
            return Ok(());
        }
    }
    
    // Find the installation script - use a more robust method to locate it
    let script_path = find_install_script()?;
    
    // Run the installation script
    let status = Command::new("sudo")
        .args(&["bash", script_path.to_str().unwrap(), 
               "--bin-dir", bin_dir.to_str().unwrap()])
        .status()
        .context("Failed to execute installation script")?;
    
    if status.success() {
        println!("VLAN CNI plugin installed successfully.");
        Ok(())
    } else {
        anyhow::bail!("Installation failed with exit code: {:?}", status.code());
    }
}

/// Find the installation script using various methods
fn find_install_script() -> Result<PathBuf> {
    // Try several possible locations
    let possible_paths = [
        // Current directory
        PathBuf::from("scripts/install.sh"),
        // Parent directory
        PathBuf::from("../scripts/install.sh"),
        // Absolute path from project root
        PathBuf::from("socni/scripts/install.sh"),
        // Environment variable
        std::env::var("SOCNI_SCRIPT_PATH").map(PathBuf::from).unwrap_or_default(),
    ];
    
    for path in &possible_paths {
        if path.exists() {
            return Ok(path.clone());
        }
    }
    
    // If we get here, we couldn't find the script
    anyhow::bail!("Installation script not found. Please specify the path with SOCNI_SCRIPT_PATH environment variable.")
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    
    // Configure logging based on verbosity
    let log_level = if cli.verbose { "debug" } else { "info" };
    std::env::set_var("RUST_LOG", log_level);
    
    let subscriber = FmtSubscriber::builder()
        .with_env_filter(EnvFilter::from_default_env())
        .finish();
    
    tracing::subscriber::set_global_default(subscriber)
        .context("Failed to set default subscriber")?;
    
    // Default tenant ID if not specified
    let tenant_id = cli.tenant_id.unwrap_or_else(|| "default".to_string());
    
    // Create Aranya client using the actual implementation from the main plugin
    let mut aranya = AranyaClient::new(cli.socket.clone(), tenant_id.clone())
        .context("Failed to initialize Aranya client")?;
    
    match cli.command {
        Commands::Create { id, master, mtu, label } => {
            // Create VLAN in Aranya
            aranya.create_vlan(id)?;
            
            // Apply labels if provided
            if !label.is_empty() {
                let labels = label.into_iter().collect::<HashMap<_, _>>();
                info!("Applying security labels to VLAN {}: {:?}", id, labels);
                // In a real implementation, we would apply these labels to the VLAN
                // For now, we'll just log them
            }
            
            println!("VLAN {} created successfully", id);
        },
        
        Commands::List { detailed } => {
            // In a real implementation, we would list VLANs from Aranya
            // For now, we'll use the status command to get VLAN information
            let status = get_vlan_status(None)?;
            
            if status.is_empty() {
                println!("No VLAN interfaces found");
            } else {
                println!("Available VLANs:");
                for vlan in status {
                    if detailed {
                        println!("  VLAN {} ({}):", vlan.id, vlan.name);
                        println!("    State: {}", vlan.state);
                        println!("    Master: {}", vlan.master);
                        
                        // Check if we have access to this VLAN
                        match aranya.check_vlan_access(vlan.id) {
                            Ok(has_access) => println!("    Access: {}", if has_access { "Granted" } else { "Denied" }),
                            Err(e) => println!("    Access: Error checking access: {}", e),
                        }
                    } else {
                        println!("  VLAN {} (master: {})", vlan.id, vlan.master);
                    }
                }
            }
        },
        
        Commands::Grant { vlan_id, target_tenant } => {
            aranya.grant_vlan_access(vlan_id, &target_tenant)?;
            println!("Access to VLAN {} granted to tenant {}", vlan_id, target_tenant);
        },
        
        Commands::Revoke { vlan_id, target_tenant } => {
            aranya.revoke_vlan_access(vlan_id, &target_tenant)?;
            println!("Access to VLAN {} revoked from tenant {}", vlan_id, target_tenant);
        },
        
        Commands::Generate { id, master, mtu, name, output, subnet, gateway } => {
            let config = generate_network_config(
                id, 
                &master, 
                mtu,
                &name,
                subnet.as_deref(),
                gateway.as_deref()
            );
            
            let config_json = serde_json::to_string_pretty(&config)?;
            
            if let Some(path) = output {
                fs::write(&path, config_json)?;
                println!("Network configuration written to {}", path.display());
            } else {
                println!("{}", config_json);
            }
        },
        
        Commands::Install { yes, bin_dir } => {
            run_install(&bin_dir, yes).await?;
        },
        
        Commands::Status { id } => {
            let status = get_vlan_status(id)?;
            
            if status.is_empty() {
                if let Some(vlan_id) = id {
                    println!("No VLAN interface with ID {} found", vlan_id);
                } else {
                    println!("No VLAN interfaces found");
                }
            } else {
                println!("VLAN Interface Status:");
                for vlan in status {
                    println!("  VLAN {} ({}):", vlan.id, vlan.name);
                    println!("    State: {}", vlan.state);
                    println!("    Master: {}", vlan.master);
                    
                    // Check if we have access to this VLAN
                    match aranya.check_vlan_access(vlan.id) {
                        Ok(has_access) => println!("    Access: {}", if has_access { "Granted" } else { "Denied" }),
                        Err(e) => println!("    Access: Error checking access: {}", e),
                    }
                }
            }
        },
    }
    
    Ok(())
}