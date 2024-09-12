package main

import (
	"errors"
	"fmt"
	"runtime"
	"strings"

	"github.com/containernetworking/cni/pkg/skel"
	"github.com/containernetworking/cni/pkg/types"
	current "github.com/containernetworking/cni/pkg/types/100"
	"github.com/containernetworking/cni/pkg/version"
	"github.com/containernetworking/plugins/pkg/ipam"
	"github.com/containernetworking/plugins/pkg/ns"
	"github.com/k8snetworkplumbingwg/sriov-cni/cnicmp/cnilogger"
	"github.com/k8snetworkplumbingwg/sriov-cni/fastiov/config"
	"github.com/k8snetworkplumbingwg/sriov-cni/fastiov/debug"
	fm "github.com/k8snetworkplumbingwg/sriov-cni/fastiov/manager"
	"github.com/k8snetworkplumbingwg/sriov-cni/pkg/sriov"
	"github.com/k8snetworkplumbingwg/sriov-cni/pkg/utils"
)

type envArgs struct {
	types.CommonArgs
	MAC types.UnmarshallableString `json:"mac,omitempty"`
}

const (
	MyCNIName                = "fastiov-cni"
	IpuAdaptionDoSaveVfInfo  = false
	IpuAdaptionDoApplyVfInfo = false
)

func init() {
	// this ensures that main runs only on main thread (thread group leader).
	// since namespace ops (unshare, setns) are done for a single thread, we
	// must ensure that the goroutine does not jump from OS thread to thread
	runtime.LockOSThread()
}

func getEnvArgs(envArgsString string) (*envArgs, error) {
	if envArgsString != "" {
		e := envArgs{}
		err := types.LoadArgs(envArgsString, &e)
		if err != nil {
			return nil, err
		}
		return &e, nil
	}
	return nil, nil
}

func cmdAdd(args *skel.CmdArgs) error {
	cnilogger.RecordStart(args.ContainerID, "CNI_conf")
	netConf, err := config.LoadConf(args.StdinData)
	if err != nil {
		return fmt.Errorf("%s failed to load netconf: %v", MyCNIName, err)
	}

	envArgs, err := getEnvArgs(args.Args)
	if err != nil {
		return fmt.Errorf("%s failed to parse args: %v", MyCNIName, err)
	}

	if envArgs != nil {
		MAC := string(envArgs.MAC)
		if MAC != "" {
			netConf.MAC = MAC
		}
	}

	netConf.MAC = strings.ToLower(netConf.MAC)
	contID := args.ContainerID[len(args.ContainerID)-8:]
	cnilogger.RecordEnd(args.ContainerID, "CNI_conf")

	cnilogger.RecordStart(args.ContainerID, "CNI_nns")
	netns, err := ns.GetNS(args.Netns)
	if err != nil {
		return fmt.Errorf("failed to open netns %q: %v", netns, err)
	}
	defer netns.Close()
	cnilogger.RecordEnd(args.ContainerID, "CNI_nns")

	cnilogger.RecordStart(args.ContainerID, "CNI_vfconf")
	sm := sriov.NewSriovManager()
	if IpuAdaptionDoApplyVfInfo {
		if err := sm.ApplyVFConfig(netConf); err != nil {
			return fmt.Errorf("SRIOV-CNI failed to configure VF %q", err)
		}
	}
	cnilogger.RecordEnd(args.ContainerID, "CNI_vfconf")

	cnilogger.RecordStart(args.ContainerID, "CNI_vfmain")
	vfDummy, err := fm.CreateVFDummyDevice(netConf, args.IfName, netns)
	cnilogger.RecordEnd(args.ContainerID, "CNI_vfmain")

	cnilogger.RecordStart(args.ContainerID, "CNI_ipam")
	// init result structure
	result := &current.Result{}
	result.Interfaces = []*current.Interface{vfDummy}

	// run the IPAM plugin
	if netConf.IPAM.Type != "" {
		var r types.Result
		r, err = ipam.ExecAdd(netConf.IPAM.Type, args.StdinData)
		if err != nil {
			return fmt.Errorf("failed to set up IPAM plugin type %q from the device %q: %v", netConf.IPAM.Type, netConf.Master, err)
		}

		defer func() {
			if err != nil {
				_ = ipam.ExecDel(netConf.IPAM.Type, args.StdinData)
			}
		}()

		// Convert the IPAM result into the current Result type
		var newResult *current.Result
		newResult, err = current.NewResultFromResult(r)
		if err != nil {
			return err
		}

		if len(newResult.IPs) == 0 {
			err = errors.New("IPAM plugin returned missing IP config")
			return err
		}

		newResult.Interfaces = result.Interfaces

		for _, ipc := range newResult.IPs {
			// All addresses apply to the container interface (move from host)
			ipc.Interface = current.Int(0)
		}

		if !netConf.DPDKMode {
			err = netns.Do(func(_ ns.NetNS) error {
				err := ipam.ConfigureIface(args.IfName, newResult)
				if err != nil {
					return err
				}

				/* After IPAM configuration is done, the following needs to handle the case of an IP address being reused by a different pods.
				 * This is achieved by sending Gratuitous ARPs and/or Unsolicited Neighbor Advertisements unconditionally.
				 * Although we set arp_notify and ndisc_notify unconditionally on the interface (please see EnableArpAndNdiscNotify()), the kernel
				 * only sends GARPs/Unsolicited NA when the interface goes from down to up, or when the link-layer address changes on the interfaces.
				 * These scenarios are perfectly valid and recommended to be enabled for optimal network performance.
				 * However for our specific case, which the kernel is unaware of, is the reuse of IP addresses across pods where each pod has a different
				 * link-layer address for it's SRIOV interface. The ARP/Neighbor cache residing in neighbors would be invalid if an IP address is reused.
				 * In order to update the cache, the GARP/Unsolicited NA packets should be sent for performance reasons. Otherwise, the neighbors
				 * may be sending packets with the incorrect link-layer address. Eventually, most network stacks would send ARPs and/or Neighbor
				 * Solicitation packets when the connection is unreachable. This would correct the invalid cache; however this may take a significant
				 * amount of time to complete.
				 *
				 * The error is ignored here because enabling this feature is only a performance enhancement.
				 */
				_ = utils.AnnounceIPs(args.IfName, newResult.IPs)
				return nil
			})
			if err != nil {
				return err
			}
		}
		result = newResult
	}
	debug.Logf("[%s]-(%s) vf ipam ok", MyCNIName, contID)
	cnilogger.RecordEnd(args.ContainerID, "CNI_ipam")
	_ = cnilogger.Stop()

	return types.PrintResult(result, netConf.CNIVersion)
}

func cmdDel(_ *skel.CmdArgs) error {
	return nil
}

func cmdCheck(_ *skel.CmdArgs) error {
	return nil
}

func main() {
	skel.PluginMain(cmdAdd, cmdCheck, cmdDel, version.All, "")
}
