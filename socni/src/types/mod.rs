use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// CNI command arguments
#[derive(Debug, Clone)]
pub struct CmdArgs {
    /// Container ID
    pub container_id: String,
    /// Network namespace path
    pub netns: String,
    /// Interface name
    pub ifname: String,
    /// Arguments
    pub args: HashMap<String, String>,
    /// Path
    pub path: String,
    /// Standard input data
    pub stdin_data: Vec<u8>,
}

/// Current result format (CNI 1.0.0)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Result {
    /// CNI specification version
    #[serde(rename = "cniVersion")]
    pub cni_version: String,
    /// Interfaces created
    pub interfaces: Option<Vec<Interface>>,
    /// IP configurations
    pub ips: Option<Vec<IPConfig>>,
    /// DNS configuration
    pub dns: Option<DNS>,
    /// Routes to configure
    pub routes: Option<Vec<Route>>,
}

/// Interface information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Interface {
    /// Interface name
    pub name: String,
    /// MAC address
    pub mac: Option<String>,
    /// Sandbox path (network namespace)
    pub sandbox: Option<String>,
}

/// IP configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IPConfig {
    /// Interface index this IP is assigned to
    pub interface: Option<usize>,
    /// IP address with prefix length
    pub address: String,
    /// Gateway
    pub gateway: Option<String>,
}

/// DNS configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DNS {
    /// DNS nameservers
    pub nameservers: Option<Vec<String>>,
    /// DNS search domains
    pub search: Option<Vec<String>>,
    /// DNS options
    pub options: Option<Vec<String>>,
}

/// Route configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Route {
    /// Destination CIDR
    pub dst: String,
    /// Gateway for this route
    pub gw: Option<String>,
}

impl Result {
    /// Create a new empty result
    pub fn new(cni_version: &str) -> Self {
        Self {
            cni_version: cni_version.to_string(),
            interfaces: None,
            ips: None,
            dns: None,
            routes: None,
        }
    }
    
    /// Add an interface to the result
    pub fn add_interface(&mut self, interface: Interface) {
        if self.interfaces.is_none() {
            self.interfaces = Some(Vec::new());
        }
        
        if let Some(interfaces) = &mut self.interfaces {
            interfaces.push(interface);
        }
    }
    
    /// Add an IP configuration to the result
    pub fn add_ip(&mut self, ip: IPConfig) {
        if self.ips.is_none() {
            self.ips = Some(Vec::new());
        }
        
        if let Some(ips) = &mut self.ips {
            ips.push(ip);
        }
    }
    
    /// Add a route to the result
    pub fn add_route(&mut self, route: Route) {
        if self.routes.is_none() {
            self.routes = Some(Vec::new());
        }
        
        if let Some(routes) = &mut self.routes {
            routes.push(route);
        }
    }
    
    /// Set DNS configuration
    pub fn set_dns(&mut self, dns: DNS) {
        self.dns = Some(dns);
    }
    
    /// Print result as JSON
    pub fn print(&self) -> anyhow::Result<()> {
        let json = serde_json::to_string_pretty(self)?;
        println!("{}", json);
        Ok(())
    }
}