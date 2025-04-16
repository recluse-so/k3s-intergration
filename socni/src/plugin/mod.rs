use anyhow::{Context, Result};
use std::process::Command;
use nix::sched::{setns, CloneFlags};
use nix::fcntl::{open, OFlag};
use nix::sys::stat::Mode;
use nix::unistd::close;
use std::os::unix::io::RawFd;
use tracing::{info, warn, error};

use crate::config::NetConf;
use crate::types::{CmdArgs, Result as CniResult, Interface, IPConfig, Route as CniRoute};

/// VLAN plugin implementation
pub struct VlanPlugin {
    /// Network configuration
    config: NetConf,
    /// Command arguments
    args: CmdArgs,
}

impl VlanPlugin {
    /// Create a new VLAN plugin
    pub fn new(config: NetConf, args: CmdArgs) -> Self {
        Self { config, args }
    }
    
    /// Add a VLAN network
    pub fn add_network(&self) -> Result<CniResult> {
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
        result.add_interface(Interface {
            name: self.args.ifname.clone(),
            mac: None,
            sandbox: Some(self.args.netns.clone()),
        });
        
        // Execute inside container network namespace
        self.in_netns(&self.args.netns, || {
            // Rename interface to requested name
            let rename_cmd = Command::new("ip")
                .args(&["link", "set", "dev", &vlan_name, "name", &self.args.ifname])
                .output()
                .context("Failed to execute ip link set name command")?;
            
            if !rename_cmd.status.success() {
                anyhow::bail!("Failed to rename VLAN interface: {}", 
                             String::from_utf8_lossy(&rename_cmd.stderr));
            }
            
            // Set interface up inside container
            let up_cmd = Command::new("ip")
                .args(&["link", "set", "dev", &self.args.ifname, "up"])
                .output()
                .context("Failed to execute ip link set up command")?;
            
            if !up_cmd.status.success() {
                anyhow::bail!("Failed to set interface up in container: {}", 
                             String::from_utf8_lossy(&up_cmd.stderr));
            }
            
            // Configure IPAM if specified
            if let Some(ipam) = &self.config.ipam {
                // In a real implementation, we'd call the IPAM plugin here
                // For simplicity, we'll just add a static IP if one is specified
                if let Some(subnet) = &ipam.subnet {
                    // Parse subnet to get a usable IP
                    let ip_parts: Vec<&str> = subnet.split('/').collect();
                    if ip_parts.len() == 2 {
                        let network = ip_parts[0];
                        let prefix = ip_parts[1];
                        
                        // Generate a simple IP from the network
                        let network_parts: Vec<&str> = network.split('.').collect();
                        if network_parts.len() == 4 {
                            let ip = format!("{}.{}.{}.100/{}", 
                                          network_parts[0], network_parts[1], 
                                          network_parts[2], prefix);
                            
                            // Add IP to interface
                            let addr_cmd = Command::new("ip")
                                .args(&["addr", "add", &ip, "dev", &self.args.ifname])
                                .output()
                                .context("Failed to execute ip addr add command")?;
                            
                            if !addr_cmd.status.success() {
                                warn!("Failed to add IP to interface: {}", 
                                     String::from_utf8_lossy(&addr_cmd.stderr));
                            } else {
                                // Add IP to result
                                result.add_ip(IPConfig {
                                    interface: Some(0),
                                    address: ip,
                                    gateway: ipam.gateway.clone(),
                                });
                                
                                // Add routes if specified
                                if let Some(routes) = &ipam.routes {
                                    for route in routes {
                                        let route_cmd = if let Some(gw) = &route.gw {
                                            Command::new("ip")
                                                .args(&["route", "add", &route.dst, "via", gw])
                                                .output()
                                        } else {
                                            Command::new("ip")
                                                .args(&["route", "add", &route.dst, "dev", &self.args.ifname])
                                                .output()
                                        };
                                        
                                        match route_cmd {
                                            Ok(output) if output.status.success() => {
                                                result.add_route(CniRoute {
                                                    dst: route.dst.clone(),
                                                    gw: route.gw.clone(),
                                                });
                                            },
                                            Ok(output) => {
                                                warn!("Failed to add route: {}", 
                                                     String::from_utf8_lossy(&output.stderr));
                                            },
                                            Err(e) => {
                                                warn!("Failed to execute ip route command: {:?}", e);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Ok(())
        })?;
        
        Ok(result)
    }
    
    /// Delete a VLAN network
    pub fn del_network(&self) -> Result<()> {
        // Clean up IPAM allocations if specified
        if let Some(ipam) = &self.config.ipam {
            // In a real implementation, we'd call the IPAM plugin to release IPs
            info!("Would release IPAM allocations for type: {}", ipam.ipam_type);
        }
        
        // The VLAN link should already be removed when the container's netns is deleted
        // But we can try to clean it up if the namespace still exists
        if let Ok(()) = self.in_netns(&self.args.netns, || {
            let del_cmd = Command::new("ip")
                .args(&["link", "delete", &self.args.ifname])
                .output()
                .context("Failed to execute ip link delete command")?;
            
            if !del_cmd.status.success() {
                warn!("Failed to delete interface in container: {}", 
                     String::from_utf8_lossy(&del_cmd.stderr));
            }
            
            Ok(())
        }) {
            info!("Cleaned up VLAN interface in container namespace");
        }
        
        Ok(())
    }
    
    /// Check a VLAN network
    pub fn check_network(&self) -> Result<()> {
        // Verify the interface exists in the container
        self.in_netns(&self.args.netns, || {
            let check_cmd = Command::new("ip")
                .args(&["link", "show", "dev", &self.args.ifname])
                .output()
                .context("Failed to execute ip link show command")?;
            
            if !check_cmd.status.success() {
                anyhow::bail!("Interface {} does not exist in container", self.args.ifname);
            }
            
            // Check if the interface is up
            let up_cmd = Command::new("ip")
                .args(&["-j", "link", "show", "dev", &self.args.ifname])
                .output()
                .context("Failed to execute ip -j link show command")?;
            
            if !up_cmd.status.success() {
                anyhow::bail!("Failed to check interface state: {}", 
                             String::from_utf8_lossy(&up_cmd.stderr));
            }
            
            // Check for "UP" in the output
            let output = String::from_utf8_lossy(&up_cmd.stdout);
            if !output.contains("\"UP\"") && !output.contains("\"state\":\"UP\"") {
                anyhow::bail!("Interface {} is not UP", self.args.ifname);
            }
            
            // Check IP configuration if IPAM was specified
            if let Some(ipam) = &self.config.ipam {
                if let Some(subnet) = &ipam.subnet {
                    let addr_cmd = Command::new("ip")
                        .args(&["-j", "addr", "show", "dev", &self.args.ifname])
                        .output()
                        .context("Failed to execute ip -j addr show command")?;
                    
                    if !addr_cmd.status.success() {
                        anyhow::bail!("Failed to check interface addresses: {}", 
                                     String::from_utf8_lossy(&addr_cmd.stderr));
                    }
                    
                    // Check that the interface has an address in the subnet
                    let output = String::from_utf8_lossy(&addr_cmd.stdout);
                    let prefix = subnet.split('/').collect::<Vec<&str>>()[1];
                    if !output.contains(&format!("/{}", prefix)) {
                        anyhow::bail!("Interface {} does not have an address in subnet {}", 
                                     self.args.ifname, subnet);
                    }
                }
            }
            
            Ok(())
        })
    }
    
    /// Verify that the master interface exists
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
    
    /// Execute a function inside a network namespace
    fn in_netns<F>(&self, netns_path: &str, f: F) -> Result<()> 
    where
        F: FnOnce() -> Result<()>
    {
        // Save the current network namespace
        let current_netns = Command::new("readlink")
            .args(&["/proc/self/ns/net"])
            .output()
            .context("Failed to read current netns")?;
        
        let current_netns = String::from_utf8_lossy(&current_netns.stdout)
            .trim()
            .to_string();
        
        // Open the target namespace
        let netns_fd = open(netns_path, OFlag::O_RDONLY, Mode::empty())
            .context("Failed to open network namespace")?;
        
        // Set namespace
        setns(netns_fd, CloneFlags::CLONE_NEWNET)
            .context("Failed to set network namespace")?;
        
        // Execute the function
        let result = f();
        
        // Close the namespace fd
        close(netns_fd)?;
        
        // Return to original namespace
        let orig_fd = open(&current_netns, OFlag::O_RDONLY, Mode::empty())
            .context("Failed to open original network namespace")?;
        
        setns(orig_fd, CloneFlags::CLONE_NEWNET)
            .context("Failed to restore original network namespace")?;
        
        close(orig_fd)?;
        
        result
    }
}