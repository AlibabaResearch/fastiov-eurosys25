package manager

import (
	"fmt"
	"net"

	current "github.com/containernetworking/cni/pkg/types/100"
	"github.com/containernetworking/plugins/pkg/ns"
	"github.com/k8snetworkplumbingwg/sriov-cni/fastiov/debug"
	sriovtypes "github.com/k8snetworkplumbingwg/sriov-cni/pkg/types"
	"github.com/vishvananda/netlink"
)

func CreateVFDummyDevice(conf *sriovtypes.NetConf, ifName string, netns ns.NetNS) (*current.Interface, error) {
	// Step 1: Communicate with a controller for checking VF status
	// TBD

	// Step 2: Create VF Dummy Device
	vfDummy := &current.Interface{}

	// deviceID := strings.ReplaceAll(strings.ReplaceAll(conf.DeviceID, ":", ""), ".", "")
	// deviceID = deviceID[4:]
	// ifName = ifName + deviceID

	if err := netns.Do(func(_ ns.NetNS) error {
		err := createVFDummyWithNetlink(conf, ifName, int(netns.Fd()))
		if err != nil {
			return err
		}

		// Re-fetch link to get all properties/attributes
		link, err := netlink.LinkByName(ifName)
		if err != nil {
			return fmt.Errorf("failed to refetch tap %q: %v", ifName, err)
		}

		// set arp up
		err = netlink.LinkSetARPOn(link)
		if err != nil {
			return fmt.Errorf("error setting ARP state: %v", err)
		}

		debug.Logf("[fastiov-cni] created dummy device with name (%s) and alias (%s)", ifName, link.Attrs().Alias)

		vfDummy.Name = link.Attrs().Name
		vfDummy.Mac = link.Attrs().HardwareAddr.String()
		vfDummy.Sandbox = netns.Path()

		return nil
	}); err != nil {
		return nil, fmt.Errorf("fail to create VF dummy device: %v", err)
	}

	return vfDummy, nil
}

func createVFDummyWithNetlink(conf *sriovtypes.NetConf, ifName string, nsFd int) error {
	linkAttrs := netlink.LinkAttrs{
		Name:      ifName,
		Namespace: netlink.NsFd(nsFd),
	}
	link := &netlink.Dummy{
		LinkAttrs: linkAttrs,
	}
	if conf.MAC != "" {
		addr, err := net.ParseMAC(conf.MAC)
		if err != nil {
			return fmt.Errorf("invalid args %v for MAC addr: %v", conf.MAC, err)
		}
		linkAttrs.HardwareAddr = addr
	}

	if err := netlink.LinkAdd(link); err != nil {
		return fmt.Errorf("failed to create VF dummy device: %v", err)
	}

	// Netlink has bugs in LinkAdd with Alias: directly setting Alias in linkAttrs results in empty configuration...
	if err := netlink.LinkSetAlias(link, conf.DeviceID); err != nil {
		return fmt.Errorf("failed to set alias (%s) for VF dummy device: %v", conf.DeviceID, err)
	}

	return nil
}
