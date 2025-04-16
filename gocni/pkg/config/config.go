package config

import (
    "encoding/json"
    "fmt"
    
    "github.com/containernetworking/cni/pkg/types"
    "example.com/vlan-cni/pkg/types"
)

// NetConf extends types.NetConf for VLAN-specific configuration
type NetConf struct {
    types.NetConf
    Master     string `json:"master"`
    VlanID     int    `json:"vlan"`
    MTU        int    `json:"mtu,omitempty"`
    IPAMConfig *types.IPAMConfig `json:"ipam"`
}

// ParseConfig parses the supplied configuration from bytes
func ParseConfig(bytes []byte) (*NetConf, error) {
    conf := &NetConf{}
    if err := json.Unmarshal(bytes, conf); err != nil {
        return nil, fmt.Errorf("failed to parse network configuration: %v", err)
    }
    
    // Validation
    if conf.VlanID < 1 || conf.VlanID > 4094 {
        return nil, fmt.Errorf("invalid VLAN ID %d (must be between 1 and 4094)", conf.VlanID)
    }
    
    if conf.Master == "" {
        return nil, fmt.Errorf("master interface name is required")
    }
    
    return conf, nil
}