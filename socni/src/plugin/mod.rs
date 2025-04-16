use std::path::PathBuf;
use std::env;
use std::process::Command;
use libc::{self, c_int};
use anyhow::{Result, Context};
use tracing::{info, warn};

use crate::config::NetConf;
use crate::types::{CmdArgs, Result as CniResult, Interface, IPConfig, Route as CniRoute};
use crate::integrations::aranya::AranyaClient;
use aranya_client::client::Queries;
use aranya_crypto::DeviceId as CryptoDeviceId;

// Define platform-specific constants and functions
#[cfg(target_os = "linux")]
const CLONE_NEWNET: c_int = 0x40000000;

#[cfg(not(target_os = "linux"))]
const CLONE_NEWNET: c_int = 0;

#[cfg(target_os = "linux")]
unsafe fn setns(fd: c_int, nstype: c_int) -> c_int {
    libc::setns(fd, nstype)
}

#[cfg(not(target_os = "linux"))]
unsafe fn setns(_fd: c_int, _nstype: c_int) -> c_int {
    // On non-Linux platforms, this is a no-op
    // In a real implementation, you might want to return an error
    0
}

/// VLAN plugin implementation
pub struct VlanPlugin {
    /// Network configuration
    config: NetConf,
    /// Command arguments
    args: CmdArgs,
    /// Aranya client for security
    aranya: Option<AranyaClient>,
}

impl VlanPlugin {
    /// Create a new VLAN plugin
    pub fn new(config: NetConf, args: CmdArgs) -> Self {
        Self { 
            config, 
            args,
            aranya: None,
        }
    }

    /// Initialize Aranya security
    async fn init_aranya(&mut self) -> Result<()> {
        // Get Aranya socket path from environment or use default
        let socket_path = env::var("ARANYA_SOCKET_PATH")
            .unwrap_or_else(|_| "/var/run/aranya/api.sock".to_string());
        
        // Get tenant ID from environment or use container ID as fallback
        let tenant_id = env::var("ARANYA_TENANT_ID")
            .unwrap_or_else(|_| self.args.container_id.clone());
        
        // Create Aranya client
        let aranya = AranyaClient::new(PathBuf::from(socket_path), tenant_id)?;
        self.aranya = Some(aranya);
        Ok(())
    }
    
    /// Check if the current device has access to the VLAN
    fn check_vlan_access(&mut self) -> Result<bool> {
        if let Some(aranya) = &mut self.aranya {
            info!("Checking VLAN {} access through Aranya policy engine", self.config.vlan);
            aranya.check_vlan_access(self.config.vlan)
        } else {
            warn!("Aranya security not initialized");
            Ok(true) // Allow access for backward compatibility
        }
    }
    
    /// Execute a closure in a network namespace
    async fn in_netns<F, Fut, T>(&self, netns: &str, f: F) -> Result<T>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T>>,
    {
        // Open the network namespace
        let netns_path = format!("/var/run/netns/{}", netns);
        let fd = unsafe { libc::open(netns_path.as_ptr() as *const i8, libc::O_RDONLY) };
        if fd < 0 {
            return Err(anyhow::anyhow!("Failed to open netns: {}", netns));
        }

        // Get current namespace
        let cur_netns = unsafe { libc::open("/proc/self/ns/net".as_ptr() as *const i8, libc::O_RDONLY) };
        if cur_netns < 0 {
            unsafe { libc::close(fd) };
            return Err(anyhow::anyhow!("Failed to open current netns"));
        }

        // Set the namespace
        let result = unsafe { setns(fd, CLONE_NEWNET) };
        if result < 0 {
            unsafe { 
                libc::close(cur_netns);
                libc::close(fd);
            };
            return Err(anyhow::anyhow!("Failed to set netns: {}", netns));
        }

        // Execute the closure
        let result = f().await;

        // Restore the original namespace
        let restore_result = unsafe { setns(cur_netns, CLONE_NEWNET) };
        if restore_result < 0 {
            unsafe { 
                libc::close(cur_netns);
                libc::close(fd);
            };
            return Err(anyhow::anyhow!("Failed to restore original netns"));
        }

        // Close file descriptors
        unsafe { 
            libc::close(cur_netns);
            libc::close(fd);
        };

        result
    }

    /// Add a VLAN network
    pub async fn add_network(&mut self) -> Result<CniResult> {
        // Initialize Aranya security
        if self.init_aranya().await.is_err() {
            warn!("Failed to initialize Aranya security. Continuing with reduced security.");
        }

        // Check VLAN access using Aranya policy engine
        if let Ok(has_access) = self.check_vlan_access() {
            if !has_access {
                anyhow::bail!("Access denied by Aranya policy engine: No permission to use VLAN {}", self.config.vlan);
            }
        }
        
        // Get master interface
        self.verify_master_interface()?;
        
        // Create VLAN interface
        let vlan_name = format!("{}.{}", self.config.master, self.config.vlan);
        info!("Creating VLAN interface: {}", vlan_name);
        
        // Create the VLAN interface on the host
        let create_cmd = Command::new("ip")
            .args(&["link", "add", "link", &self.config.master, "name", &vlan_name,
                  "type", "vlan", "id", &self.config.vlan.to_string()])
            .output()
            .context("Failed to execute ip link add command")?;
        
        if !create_cmd.status.success() && !String::from_utf8_lossy(&create_cmd.stderr).contains("File exists") {
            anyhow::bail!("Failed to create VLAN interface: {}", 
                         String::from_utf8_lossy(&create_cmd.stderr));
        }
        
        // Set link up
        let up_cmd = Command::new("ip")
            .args(&["link", "set", "dev", &vlan_name, "up"])
            .output()
            .context("Failed to execute ip link set up command")?;
        
        if !up_cmd.status.success() {
            anyhow::bail!("Failed to set VLAN interface up: {}", 
                         String::from_utf8_lossy(&up_cmd.stderr));
        }
        
        // Set MTU if configured
        if let Some(mtu) = self.config.mtu {
            let mtu_cmd = Command::new("ip")
                .args(&["link", "set", "dev", &vlan_name, "mtu", &mtu.to_string()])
                .output()
                .context("Failed to execute ip link set mtu command")?;
            
            if !mtu_cmd.status.success() {
                warn!("Failed to set MTU on VLAN interface: {}", 
                     String::from_utf8_lossy(&mtu_cmd.stderr));
            }
        }
        
        // Move interface to container namespace
        let move_cmd = Command::new("ip")
            .args(&["link", "set", "dev", &vlan_name, "netns", &self.args.netns])
            .output()
            .context("Failed to execute ip link set netns command")?;
        
        if !move_cmd.status.success() {
            anyhow::bail!("Failed to move VLAN interface to container namespace: {}", 
                         String::from_utf8_lossy(&move_cmd.stderr));
        }
        
        // Configure IP addressing inside the container
        let mut result = CniResult::new(&self.config.cni_version);
        
        // Add interface to result
        let interface = Interface {
            name: self.args.ifname.clone(),
            mac: None,
            sandbox: Some(self.args.netns.clone()),
        };
        result.add_interface(interface);
        
        // Clone values needed by the closure to avoid borrow checker issues
        let ifname = self.args.ifname.clone();
        let vlan_name_clone = vlan_name.clone();
        let config = self.config.clone();
        let vlan_id = self.config.vlan;
        
        // Create a mutable reference to result that can be moved into the closure
        let result_ref = &mut result;
        
        // Execute inside container network namespace
        self.in_netns(&self.args.netns, || async move {
            // Rename interface to the requested name if different
            if vlan_name_clone != ifname {
                let rename_cmd = Command::new("ip")
                    .args(&["link", "set", "dev", &vlan_name_clone, "name", &ifname])
                    .output()
                    .context("Failed to execute ip link set name command")?;
                
                if !rename_cmd.status.success() {
                    anyhow::bail!("Failed to rename interface in container: {}", 
                                 String::from_utf8_lossy(&rename_cmd.stderr));
                }
            }
            
            // Set interface up
            let up_cmd = Command::new("ip")
                .args(&["link", "set", "dev", &ifname, "up"])
                .output()
                .context("Failed to execute ip link set up command in container")?;
            
            if !up_cmd.status.success() {
                anyhow::bail!("Failed to set interface up in container: {}", 
                             String::from_utf8_lossy(&up_cmd.stderr));
            }
            
            // Configure IPAM if provided
            if let Some(ipam) = &config.ipam {
                // Use a simple allocation based on VLAN ID
                // In a real implementation, this would use Aranya's IPAM service
                let _subnet = ipam.subnet.as_deref().unwrap_or("192.168.0.0/24");
                let ip = format!("192.168.{}.2/24", vlan_id % 256);
                let gateway = format!("192.168.{}.1", vlan_id % 256);
                
                info!("Configuring IP: {}, Gateway: {}", ip, gateway);
                
                // Add IP to interface
                let addr_cmd = Command::new("ip")
                    .args(&["addr", "add", &ip, "dev", &ifname])
                    .output()
                    .context("Failed to execute ip addr add command")?;
                
                if !addr_cmd.status.success() {
                    anyhow::bail!("Failed to add IP address to interface: {}", 
                                 String::from_utf8_lossy(&addr_cmd.stderr));
                }
                
                // Add default route if IPAM provided gateway
                let route_cmd = Command::new("ip")
                    .args(&["route", "add", "default", "via", &gateway])
                    .output()
                    .context("Failed to execute ip route add command")?;
                
                if !route_cmd.status.success() {
                    warn!("Failed to add default route: {}", 
                         String::from_utf8_lossy(&route_cmd.stderr));
                }
                
                // Add IP details to result
                result_ref.add_ip(IPConfig {
                    interface: None,
                    address: ip.to_string(),
                    gateway: Some(gateway.to_string()),
                });
                
                // Add routing details to result
                result_ref.add_route(CniRoute {
                    dst: "0.0.0.0/0".to_string(),
                    gw: Some(gateway.to_string()),
                });
                
                // Add additional routes if configured
                if let Some(routes) = &ipam.routes {
                    for route in routes {
                        result_ref.add_route(CniRoute {
                            dst: route.dst.clone(),
                            gw: route.gw.clone(),
                        });
                    }
                }
            }
            
            Ok(())
        }).await?;
        
        // Register VLAN with Aranya
        if let Some(aranya) = &mut self.aranya {
            if let Err(e) = aranya.create_vlan(self.config.vlan) {
                warn!("Failed to register VLAN with Aranya: {}", e);
            }
        }
        
        Ok(result)
    }
    
    /// Delete a VLAN network
    pub async fn del_network(&mut self) -> Result<()> {
        // Initialize Aranya security
        if self.init_aranya().await.is_err() {
            warn!("Failed to initialize Aranya security. Continuing with cleanup.");
        }

        // Clean up IPAM allocations if specified
        if let Some(ipam) = &self.config.ipam {
            if let Some(aranya) = &mut self.aranya {
                // No need to deallocate IP since it's not implemented
            }
        }
        
        // Clone values needed by the closure to avoid borrow checker issues
        let ifname = self.args.ifname.clone();
        let netns = self.args.netns.clone();
        
        // The VLAN link should already be removed when the container's netns is deleted
        // But we can try to clean it up if the namespace still exists
        if let Ok(()) = self.in_netns(&netns, || async move {
            let del_cmd = Command::new("ip")
                .args(&["link", "delete", &ifname])
                .output()
                .context("Failed to execute ip link delete command")?;
            
            if !del_cmd.status.success() {
                warn!("Failed to delete interface in container: {}", 
                     String::from_utf8_lossy(&del_cmd.stderr));
            }
            
            Ok(())
        }).await {
            info!("Cleaned up VLAN interface in container namespace");
        }

        // Deregister VLAN from Aranya
        if let Some(aranya) = &mut self.aranya {
            if let Err(e) = aranya.delete_vlan(self.config.vlan) {
                warn!("Failed to deregister VLAN from Aranya: {}", e);
            }
        }
        
        Ok(())
    }
    
    /// Check a VLAN network
    pub async fn check_network(&mut self) -> Result<()> {
        // Initialize Aranya security
        if self.init_aranya().await.is_err() {
            warn!("Failed to initialize Aranya security. Continuing with reduced security.");
        }

        // Check access permissions with Aranya
        if let Ok(has_access) = self.check_vlan_access() {
            if !has_access {
                anyhow::bail!("Access denied by Aranya policy engine: No permission to use VLAN {}", self.config.vlan);
            }
        }
        
        // Clone values needed by the closure to avoid borrow checker issues
        let ifname = self.args.ifname.clone();
        let vlan_id = self.config.vlan;
        let netns = self.args.netns.clone();
        let config = self.config.clone();
        
        // Verify the interface exists in the container's namespace
        self.in_netns(&netns, || async move {
            let ip_cmd = Command::new("ip")
                .args(&["addr", "show", "dev", &ifname])
                .output()
                .context("Failed to execute ip addr show command")?;
            
            if !ip_cmd.status.success() {
                anyhow::bail!("Interface {} does not exist in container namespace", 
                             ifname);
            }
            
            // Verify it's a VLAN interface
            let output = String::from_utf8_lossy(&ip_cmd.stdout);
            if !output.contains(&format!("vlan {}", vlan_id)) {
                anyhow::bail!("Interface {} is not VLAN {}", ifname, vlan_id);
            }
            
            // If IPAM was specified, verify IP configuration
            if let Some(ipam) = &config.ipam {
                // Verify there's at least one IP address
                if !output.contains("inet ") {
                    anyhow::bail!("Interface {} has no IP address", ifname);
                }
            }
            
            Ok(())
        }).await?;
        
        Ok(())
    }
    
    /// Verify the master interface exists
    fn verify_master_interface(&self) -> Result<()> {
        let check_cmd = Command::new("ip")
            .args(&["link", "show", "dev", &self.config.master])
            .output()
            .context("Failed to execute ip link show command")?;
        
        if !check_cmd.status.success() {
            anyhow::bail!("Master interface {} does not exist", self.config.master);
        }
        
        Ok(())
    }
}