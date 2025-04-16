//! VLAN CNI plugin for Kubernetes
//! 
//! This implementation provides a pure Rust VLAN CNI plugin that:
//! - Creates VLAN interfaces on the host
//! - Moves them into container namespaces
//! - Configures IP addresses
//! - Handles cleanup on container deletion

pub mod config;
pub mod plugin;
pub mod types;
pub mod commands;

// Re-export commonly used items
pub use config::NetConf;
pub use plugin::VlanPlugin;
pub use commands::{run_cni, cmd_add, cmd_del, cmd_check};