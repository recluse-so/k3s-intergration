// File: socni/tests/policies/vlan_policy.rs

use aranya_crypto::{aead::Aead, default::DefaultEngine, CipherSuite};
use aranya_crypto::keystore::fs_keystore::Store;
use aranya_daemon_api::CS;
use aranya_daemon::policy::{Effect, Permission};
use aranya_daemon::vm_policy::PolicyEngine;

// Define the policy rules for VLAN access
pub const TEST_VLAN_POLICY: &str = r#"
{
    "version": "1.0",
    "policy_name": "vlan_access_policy",
    "rules": [
        {
            "id": "admin_full_access",
            "subjects": ["tenant:admin"],
            "permissions": ["sdwan:admin"],
            "effect": "allow"
        },
        {
            "id": "tenant1_vlan_access",
            "subjects": ["tenant:tenant1"],
            "permissions": ["sdwan:access_vlan:100", "sdwan:access_vlan:200"],
            "effect": "allow"
        },
        {
            "id": "tenant2_vlan_access",
            "subjects": ["tenant:tenant2"],
            "permissions": ["sdwan:access_vlan:200"],
            "effect": "allow"
        },
        {
            "id": "tenant_operations",
            "subjects": ["tenant:*"],
            "permissions": ["sdwan:list_vlans"],
            "effect": "allow"
        }
    ]
}
"#;

/// Creates a test PolicyEngine with VLAN access rules
pub fn create_test_policy_engine() -> PolicyEngine<DefaultEngine, Store> {
    // You'd typically load this from storage in a real environment
    let mock_device_id = [0u8; 32];
    
    // Create a test keystore in memory/temp directory
    let temp_dir = tempfile::tempdir().unwrap();
    let keystore = Store::open(temp_dir.path()).unwrap();
    
    // Create a test crypto engine
    let key_bytes = [0u8; 32]; // Test key, not for production
    let key = <<CS as CipherSuite>::Aead as Aead>::Key::from_slice(&key_bytes).unwrap();
    let engine = DefaultEngine::new(&key, aranya_crypto::default::Rng);
    
    // Create the policy engine with our test policy
    PolicyEngine::new_from_json(TEST_VLAN_POLICY, engine, keystore, mock_device_id).unwrap()
}