use anyhow::{Context, Result};
use std::collections::HashMap;
use std::env;
use std::io::{self, Read};
use tokio::runtime::Runtime;

use crate::config::NetConf;
use crate::plugin::VlanPlugin;
use crate::types::CmdArgs;

/// Parse command arguments from environment
pub fn parse_args() -> Result<CmdArgs> {
    // Get required environment variables
    let container_id = env::var("CNI_CONTAINERID")
        .context("CNI_CONTAINERID not found in environment")?;
    
    let netns = env::var("CNI_NETNS")
        .context("CNI_NETNS not found in environment")?;
    
    let ifname = env::var("CNI_IFNAME")
        .context("CNI_IFNAME not found in environment")?;
    
    let path = env::var("CNI_PATH")
        .context("CNI_PATH not found in environment")?;
    
    // Get args (if any)
    let args_str = env::var("CNI_ARGS").unwrap_or_default();
    let args = parse_cni_args(&args_str);
    
    // Read stdin data
    let mut stdin_data = Vec::new();
    io::stdin().read_to_end(&mut stdin_data)
        .context("Failed to read from stdin")?;
    
    Ok(CmdArgs {
        container_id,
        netns,
        ifname,
        args,
        path,
        stdin_data,
    })
}

/// Parse CNI_ARGS string into key-value pairs
fn parse_cni_args(args_str: &str) -> HashMap<String, String> {
    let mut args = HashMap::new();
    
    if !args_str.is_empty() {
        for pair in args_str.split(';') {
            if let Some(idx) = pair.find('=') {
                let key = pair[..idx].to_string();
                let value = pair[idx+1..].to_string();
                args.insert(key, value);
            }
        }
    }
    
    args
}

/// Execute the add command
pub fn cmd_add() -> Result<()> {
    let args = parse_args()?;
    
    // Parse network configuration
    let conf = NetConf::parse(&args.stdin_data)?;
    
    // Create plugin and add network
    let mut plugin = VlanPlugin::new(conf, args);
    
    // Create a runtime to execute async code
    let runtime = Runtime::new().context("Failed to create Tokio runtime")?;
    let result = runtime.block_on(plugin.add_network())?;
    
    // Output result as JSON
    result.print()?;
    
    Ok(())
}

/// Execute the delete command
pub fn cmd_del() -> Result<()> {
    let args = parse_args()?;
    
    // Parse network configuration
    let conf = NetConf::parse(&args.stdin_data)?;
    
    // Create plugin and delete network
    let mut plugin = VlanPlugin::new(conf, args);
    
    // Create a runtime to execute async code
    let runtime = Runtime::new().context("Failed to create Tokio runtime")?;
    runtime.block_on(plugin.del_network())?;
    
    Ok(())
}

/// Execute the check command
pub fn cmd_check() -> Result<()> {
    let args = parse_args()?;
    
    // Parse network configuration
    let conf = NetConf::parse(&args.stdin_data)?;
    
    // Create plugin and check network
    let mut plugin = VlanPlugin::new(conf, args);
    
    // Create a runtime to execute async code
    let runtime = Runtime::new().context("Failed to create Tokio runtime")?;
    runtime.block_on(plugin.check_network())?;
    
    Ok(())
}

/// Main entry point for the CNI plugin
pub fn run_cni() -> Result<()> {
    // Get command from environment
    let cmd = env::var("CNI_COMMAND")
        .context("CNI_COMMAND not found in environment")?;
    
    // Execute the appropriate command
    match cmd.as_str() {
        "ADD" => cmd_add(),
        "DEL" => cmd_del(),
        "CHECK" => cmd_check(),
        "VERSION" => {
            // Output supported CNI versions
            println!(r#"{{"cniVersion":"1.0.0","supportedVersions":["0.3.0","0.3.1","0.4.0","1.0.0"]}}"#);
            Ok(())
        },
        _ => anyhow::bail!("Unknown CNI command: {}", cmd),
    }
}