package config

import (
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"

	"github.com/containernetworking/cni/pkg/skel"
	"github.com/k8snetworkplumbingwg/sriov-cni/fastiov/debug"
	futils "github.com/k8snetworkplumbingwg/sriov-cni/fastiov/utils"
	sriovtypes "github.com/k8snetworkplumbingwg/sriov-cni/pkg/types"
	"github.com/k8snetworkplumbingwg/sriov-cni/pkg/utils"
)

var (
	// DefaultCNIDir used for caching NetConf
	DefaultCNIDir = "/tmp/pod_test/fastiov-conf"
	MyCNIName     = "fastiov-cni"
	NumVlanQos    = 8
)

// LoadConf parses and validates stdin netconf and returns NetConf object
func LoadConf(bytes []byte) (*sriovtypes.NetConf, error) {
	n := &sriovtypes.NetConf{}
	if err := json.Unmarshal(bytes, n); err != nil {
		return nil, fmt.Errorf("LoadConf(): failed to load netconf: %v", err)
	}

	if tenantIDData, ok := n.RuntimeConfig["tenantID"]; ok {
		tenantID, err := futils.ExtractIntRuntimeConfig(tenantIDData)
		if err != nil {
			return nil, fmt.Errorf("no valid tenantID in RuntimeConfig found for %s: %v", MyCNIName, err)
		} else if tenantID <= 0 {
			return nil, fmt.Errorf("invalid tenantID (%d) in RuntimeConfig found for %s: %v", tenantID, MyCNIName, err)
		}
		n.TenantID = tenantID
	} else {
		return nil, fmt.Errorf("no tenantID in RuntimeConfig found for %s", MyCNIName)
	}

	if tenantPodIndexData, ok := n.RuntimeConfig["tenantPodIndex"]; ok {
		tenantPodIndex, err := futils.ExtractIntRuntimeConfig(tenantPodIndexData)
		if err != nil {
			return nil, fmt.Errorf("no valid tenantPodIndex in RuntimeConfig found for %s: %v", MyCNIName, err)
		} else if tenantPodIndex <= 0 {
			return nil, fmt.Errorf("invalid tenantPodIndex (%d) in RuntimeConfig found for %s: %v", tenantPodIndex, MyCNIName, err)
		}
		n.TenantPodIndex = tenantPodIndex
	} else {
		return nil, fmt.Errorf("no tenantPodIndex in RuntimeConfig found for %s", MyCNIName)
	}

	if n.DeviceID == "" {
		deviceID, err := futils.HackDeviceIDWithFixedConf(n.TenantID, n.TenantPodIndex)
		if err != nil {
			return nil, fmt.Errorf("device id hacking error: %v", err)
		}
		n.DeviceID = deviceID
	}

	if n.Vlan == nil {
		vlan := n.TenantID
		n.Vlan = &vlan
		if n.VlanQoS == nil {
			vlanQos := n.TenantPodIndex % NumVlanQos
			n.VlanQoS = &vlanQos
		}
	}

	// DeviceID takes precedence; if we are given a VF pciaddr then work from there
	if n.DeviceID != "" {
		// Get rest of the VF information
		// even VF is binded to VFIO, this function also returns the correct value of pfName and vfID
		pfName, vfID, err := getVfInfo(n.DeviceID)
		if err != nil {
			return nil, fmt.Errorf("LoadConf(): failed to get VF information: %q", err)
		}
		n.VFID = vfID
		n.Master = pfName
	} else {
		return nil, fmt.Errorf("LoadConf(): VF pci addr is required")
	}

	debug.Logf("[%s] creating cni for tenant-%d.%d on vf (addr=%s, vfid=%d, pf=%s) with vlan=%d(qos=%d)\n",
		MyCNIName,
		n.TenantID, n.TenantPodIndex,
		n.DeviceID, n.VFID, n.Master,
		*n.Vlan, *n.VlanQoS,
	)

	if n.Vlan == nil {
		vlan := 0
		n.Vlan = &vlan
	}

	// validate vlan id range
	if *n.Vlan < 0 || *n.Vlan > 4094 {
		return nil, fmt.Errorf("LoadConf(): vlan id %d invalid: value must be in the range 0-4094", *n.Vlan)
	}

	if n.VlanQoS == nil {
		qos := 0
		n.VlanQoS = &qos
	}

	// validate that VLAN QoS is in the 0-7 range
	if *n.VlanQoS < 0 || *n.VlanQoS > 7 {
		return nil, fmt.Errorf("LoadConf(): vlan QoS PCP %d invalid: value must be in the range 0-7", *n.VlanQoS)
	}

	// validate non-zero value for vlan id if vlan qos is set to a non-zero value
	if *n.VlanQoS != 0 && *n.Vlan == 0 {
		return nil, fmt.Errorf("LoadConf(): non-zero vlan id must be configured to set vlan QoS to a non-zero value")
	}

	if n.VlanProto == nil {
		proto := sriovtypes.Proto8021q
		n.VlanProto = &proto
	}

	*n.VlanProto = strings.ToLower(*n.VlanProto)
	if *n.VlanProto != sriovtypes.Proto8021ad && *n.VlanProto != sriovtypes.Proto8021q {
		return nil, fmt.Errorf("LoadConf(): vlan Proto %s invalid: value must be '802.1Q' or '802.1ad'", *n.VlanProto)
	}

	// validate non-zero value for vlan id if vlan proto is set to 802.1ad
	if *n.VlanProto == sriovtypes.Proto8021ad && *n.Vlan == 0 {
		return nil, fmt.Errorf("LoadConf(): non-zero vlan id must be configured to set vlan proto 802.1ad")
	}

	// validate that link state is one of supported values
	if n.LinkState != "" && n.LinkState != "auto" && n.LinkState != "enable" && n.LinkState != "disable" {
		return nil, fmt.Errorf("LoadConf(): invalid link_state value: %s", n.LinkState)
	}

	return n, nil
}

func getVfInfo(vfPci string) (string, int, error) {
	var vfID int

	pf, err := utils.GetPfName(vfPci)
	if err != nil {
		return "", vfID, err
	}

	vfID, err = utils.GetVfid(vfPci, pf)
	if err != nil {
		return "", vfID, err
	}

	return pf, vfID, nil
}

// LoadConfFromCache retrieves cached NetConf returns it along with a handle for removal
func LoadConfFromCache(args *skel.CmdArgs) (*sriovtypes.NetConf, string, error) {
	netConf := &sriovtypes.NetConf{}

	s := []string{args.ContainerID, args.IfName}
	cRef := strings.Join(s, "-")
	cRefPath := filepath.Join(DefaultCNIDir, cRef)

	netConfBytes, err := utils.ReadScratchNetConf(cRefPath)
	if err != nil {
		return nil, "", fmt.Errorf("error reading cached NetConf in %s with name %s", DefaultCNIDir, cRef)
	}

	if err = json.Unmarshal(netConfBytes, netConf); err != nil {
		return nil, "", fmt.Errorf("failed to parse NetConf: %q", err)
	}

	return netConf, cRefPath, nil
}

// GetMacAddressForResult return the mac address we should report to the CNI call return object
// if the device is on kernel mode we report that one back
// if not we check the administrative mac address on the PF
// if it is set and is not zero, report it.
func GetMacAddressForResult(netConf *sriovtypes.NetConf) string {
	if netConf.MAC != "" {
		return netConf.MAC
	}
	if !netConf.DPDKMode {
		return netConf.OrigVfState.EffectiveMAC
	}
	if netConf.OrigVfState.AdminMAC != "00:00:00:00:00:00" {
		return netConf.OrigVfState.AdminMAC
	}

	return ""
}
