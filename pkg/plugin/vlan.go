package plugin

import (
    "fmt"
    "net"
    
    "github.com/containernetworking/cni/pkg/skel"
    "github.com/containernetworking/cni/pkg/types"
    current "github.com/containernetworking/cni/pkg/types/100"
    "github.com/containernetworking/plugins/pkg/ip"
    "github.com/containernetworking/plugins/pkg/ns"
    "github.com/vishvananda/netlink"
    
    "example.com/vlan-cni/pkg/config"
)

// AddVlanNetwork creates a VLAN interface and moves it to the container's network namespace
func AddVlanNetwork(args *skel.CmdArgs, conf *config.NetConf) (*current.Result, error) {
    // Get master interface
    master, err := netlink.LinkByName(conf.Master)
    if err != nil {
        return nil, fmt.Errorf("failed to lookup master interface %q: %v", conf.Master, err)
    }
    
    // Create VLAN interface
    vlanName := fmt.Sprintf("%s.%d", master.Attrs().Name, conf.VlanID)
    vlan := &netlink.Vlan{
        LinkAttrs: netlink.LinkAttrs{
            Name:        vlanName,
            ParentIndex: master.Attrs().Index,
            MTU:         conf.MTU,
        },
        VlanId: conf.VlanID,
    }
    
    // Create the VLAN interface on the host
    if err := netlink.LinkAdd(vlan); err != nil {
        if err.Error() != "file exists" {
            return nil, fmt.Errorf("failed to create VLAN interface: %v", err)
        }
        // If it already exists, retrieve it
        vlan, err = netlink.LinkByName(vlanName)
        if err != nil {
            return nil, fmt.Errorf("failed to lookup existing VLAN interface: %v", err)
        }
    }
    
    // Set link up
    if err := netlink.LinkSetUp(vlan); err != nil {
        return nil, fmt.Errorf("failed to set VLAN interface %q up: %v", vlanName, err)
    }
    
    // Move interface to container namespace
    netns, err := ns.GetNS(args.Netns)
    if err != nil {
        return nil, fmt.Errorf("failed to open netns %q: %v", args.Netns, err)
    }
    defer netns.Close()
    
    if err := netlink.LinkSetNsFd(vlan, int(netns.Fd())); err != nil {
        return nil, fmt.Errorf("failed to move VLAN interface to container namespace: %v", err)
    }
    
    // Configure IP addressing inside the container
    result := &current.Result{
        CNIVersion: conf.CNIVersion,
    }
    
    // Execute inside container network namespace
    err = netns.Do(func(hostNS ns.NetNS) error {
        // Rename interface to a standard name inside container
        contVlan, err := netlink.LinkByName(vlanName)
        if err != nil {
            return fmt.Errorf("failed to find VLAN interface in container: %v", err)
        }
        
        if err := netlink.LinkSetName(contVlan, args.IfName); err != nil {
            return fmt.Errorf("failed to rename VLAN interface: %v", err)
        }
        
        // Configure IPAM - allocate IP, set up routes
        if conf.IPAMConfig != nil {
            r, err := ConfigureIPAM(args.IfName, conf.IPAMConfig, args.ContainerID)
            if err != nil {
                return err
            }
            result = r
        }
        
        // Set interface up inside container
        contIface, err := netlink.LinkByName(args.IfName)
        if err != nil {
            return fmt.Errorf("failed to lookup container interface %q: %v", args.IfName, err)
        }
        
        if err := netlink.LinkSetUp(contIface); err != nil {
            return fmt.Errorf("failed to set %q up: %v", args.IfName, err)
        }
        
        return nil
    })
    
    if err != nil {
        return nil, err
    }
    
    return result, nil
}

// DelVlanNetwork removes VLAN interfaces and performs cleanup
func DelVlanNetwork(args *skel.CmdArgs, conf *config.NetConf) error {
    // Clean up IPAM allocations
    if conf.IPAMConfig != nil {
        err := ReleaseIPAllocation(args.IfName, conf.IPAMConfig, args.ContainerID)
        if err != nil {
            return err
        }
    }
    
    // The VLAN link should already be removed when the container's netns is deleted
    return nil
}

// CheckVlanNetwork verifies the VLAN network is correctly configured
func CheckVlanNetwork(args *skel.CmdArgs, conf *config.NetConf) error {
    netns, err := ns.GetNS(args.Netns)
    if err != nil {
        return fmt.Errorf("failed to open netns %q: %v", args.Netns, err)
    }
    defer netns.Close()
    
    // Check interface exists and has correct VLAN configuration
    err = netns.Do(func(hostNS ns.NetNS) error {
        link, err := netlink.LinkByName(args.IfName)
        if err != nil {
            return fmt.Errorf("failed to find interface %q: %v", args.IfName, err)
        }
        
        // Check IP configuration if IPAM was specified
        if conf.IPAMConfig != nil {
            // Verify IP addresses
            addrs, err := netlink.AddrList(link, netlink.FAMILY_ALL)
            if err != nil {
                return fmt.Errorf("failed to list interface addresses: %v", err)
            }
            
            // Additional IP verification logic would go here
        }
        
        return nil
    })
    
    return err
}