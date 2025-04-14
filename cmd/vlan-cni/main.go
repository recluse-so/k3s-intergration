package main

import (
    "encoding/json"
    "fmt"
    "os"

    "github.com/containernetworking/cni/pkg/skel"
    "github.com/containernetworking/cni/pkg/types"
    current "github.com/containernetworking/cni/pkg/types/100"
    "github.com/containernetworking/cni/pkg/version"
    
    "example.com/vlan-cni/pkg/plugin"
    "example.com/vlan-cni/pkg/config"
)

func main() {
    skel.PluginMain(cmdAdd, cmdCheck, cmdDel, version.All, "VLAN CNI plugin v0.1.0")
}

func cmdAdd(args *skel.CmdArgs) error {
    conf, err := config.ParseConfig(args.StdinData)
    if err != nil {
        return err
    }
    
    result, err := plugin.AddVlanNetwork(args, conf)
    if err != nil {
        return err
    }
    
    return types.PrintResult(result, conf.CNIVersion)
}

func cmdDel(args *skel.CmdArgs) error {
    conf, err := config.ParseConfig(args.StdinData)
    if err != nil {
        return err
    }
    
    return plugin.DelVlanNetwork(args, conf)
}

func cmdCheck(args *skel.CmdArgs) error {
    conf, err := config.ParseConfig(args.StdinData)
    if err != nil {
        return err
    }
    
    return plugin.CheckVlanNetwork(args, conf)
}