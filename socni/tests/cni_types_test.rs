use std::collections::HashMap;
use std::path::PathBuf;

use socni::config::NetConf;
use socni::plugin::VlanPlugin;
use socni::types::{CmdArgs, Result as CniResult, Interface, IPConfig, Route, DNS};

#[test]
fn test_net_conf_creation() -> Result<(), Box<dyn std::error::Error>> {
    let conf = NetConf {
        cni_version: "1.0.0".to_string(),
        name: "test-vlan".to_string(),
        plugin_type: "vlan".to_string(),
        master: "eth0".to_string(),
        vlan: 100,
        mtu: Some(1500),
        ipam: None,
    };

    assert_eq!(conf.cni_version, "1.0.0");
    assert_eq!(conf.name, "test-vlan");
    assert_eq!(conf.plugin_type, "vlan");
    assert_eq!(conf.master, "eth0");
    assert_eq!(conf.vlan, 100);
    assert_eq!(conf.mtu, Some(1500));
    assert!(conf.ipam.is_none());

    Ok(())
}

#[test]
fn test_cmd_args_creation() -> Result<(), Box<dyn std::error::Error>> {
    let conf = NetConf {
        cni_version: "1.0.0".to_string(),
        name: "test-vlan".to_string(),
        plugin_type: "vlan".to_string(),
        master: "eth0".to_string(),
        vlan: 100,
        mtu: Some(1500),
        ipam: None,
    };

    let args = CmdArgs {
        container_id: "test-container".to_string(),
        netns: "/var/run/netns/test".to_string(),
        ifname: "eth1".to_string(),
        args: HashMap::new(),
        path: "/opt/cni/bin".to_string(),
        stdin_data: serde_json::to_vec(&conf)?,
    };

    assert_eq!(args.container_id, "test-container");
    assert_eq!(args.netns, "/var/run/netns/test");
    assert_eq!(args.ifname, "eth1");
    assert!(args.args.is_empty());
    assert_eq!(args.path, "/opt/cni/bin");
    assert!(!args.stdin_data.is_empty());

    Ok(())
}

#[test]
fn test_vlan_plugin_creation() -> Result<(), Box<dyn std::error::Error>> {
    let conf = NetConf {
        cni_version: "1.0.0".to_string(),
        name: "test-vlan".to_string(),
        plugin_type: "vlan".to_string(),
        master: "eth0".to_string(),
        vlan: 100,
        mtu: Some(1500),
        ipam: None,
    };

    let args = CmdArgs {
        container_id: "test-container".to_string(),
        netns: "/var/run/netns/test".to_string(),
        ifname: "eth1".to_string(),
        args: HashMap::new(),
        path: "/opt/cni/bin".to_string(),
        stdin_data: serde_json::to_vec(&conf)?,
    };

    let plugin = VlanPlugin::new(conf.clone(), args.clone());
    
    // Test that the plugin was created successfully
    // Note: We can't directly access the internal fields of VlanPlugin
    // Instead, we'll test that it was created without errors
    
    Ok(())
}

#[test]
fn test_cni_result_serialization() -> Result<(), Box<dyn std::error::Error>> {
    let result = CniResult {
        cni_version: "1.0.0".to_string(),
        interfaces: Some(vec![]),
        ips: Some(vec![]),
        routes: Some(vec![]),
        dns: None,
    };

    let serialized = serde_json::to_string(&result)?;
    let deserialized: CniResult = serde_json::from_str(&serialized)?;

    assert_eq!(result.cni_version, deserialized.cni_version);
    assert!(result.interfaces.is_some() && deserialized.interfaces.is_some());
    assert!(result.ips.is_some() && deserialized.ips.is_some());
    assert!(result.routes.is_some() && deserialized.routes.is_some());
    assert!(result.dns.is_none() && deserialized.dns.is_none());

    Ok(())
} 