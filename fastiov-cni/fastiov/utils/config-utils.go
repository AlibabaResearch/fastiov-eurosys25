package utils

import (
	"fmt"
	"strconv"
)

// var (
// 	vfAddrList    = []string{}
// 	busPrefix     = "0000:cb:"
// 	deviceLimit   = 128
// 	functionLimit = 8
// 	numVFs        = 256
// )

// func init() {
// 	curVFs := 0
// 	for device := 0; device < deviceLimit; device++ {
// 		for function := 0; function < functionLimit; function++ {
// 			if curVFs < numVFs {
// 				bdf := fmt.Sprintf("%s%02x.%d", busPrefix, device, function)
// 				vfAddrList = append(vfAddrList, bdf)
// 				curVFs++
// 			}
// 		}
// 	}
// }

var (
	vfAddrList    = []string{}
	busPrefix     = "0000:65:"
	deviceLimit   = 128
	functionLimit = 8
	numVFs        = 200
)

func init() {
	curVFs := 0
	for device := 1; device < deviceLimit; device++ {
		for function := 0; function < functionLimit; function++ {
			if curVFs < numVFs/2 {
				bdf := fmt.Sprintf("%s%02x.%d", busPrefix, device, function)
				vfAddrList = append(vfAddrList, bdf)
				curVFs++
			}
		}
	}

	curVFs = 0
	for device := 17; device < deviceLimit; device++ {
		for function := 0; function < functionLimit; function++ {
			if curVFs < numVFs/2 {
				bdf := fmt.Sprintf("%s%02x.%d", busPrefix, device, function)
				vfAddrList = append(vfAddrList, bdf)
				curVFs++
			}
		}
	}
}

func ExtractIntRuntimeConfig(confData interface{}) (int, error) {
	confStr, ok := confData.(string)
	if !ok {
		return 0, fmt.Errorf("convert string error")
	}
	if confInt, err := strconv.Atoi(confStr); err == nil {
		return confInt, nil
	}
	return 0, fmt.Errorf("convert int error")
}

func ExtractStrRuntimeConfig(confData interface{}) (string, error) {
	confStr, ok := confData.(string)
	if !ok {
		return "", fmt.Errorf("convert string error")
	}
	return confStr, nil
}

func HackDeviceIDWithFixedConf(tenantID int, tenantPodIndex int) (string, error) {
	// direct maping tenantID to vf
	if tenantID > numVFs {
		return "", fmt.Errorf("Pod %d-%d out of VF range [1, %d]", tenantID, tenantPodIndex, numVFs)
	}
	return vfAddrList[(tenantID-1)%numVFs], nil
}
