#!/bin/bash
TIME_MILLI="date +%s%3N"
start_time=$($TIME_MILLI)

echo $1 > /sys/bus/pci/devices/0000:65:00.0/sriov_numvfs 
echo $1 > /sys/bus/pci/devices/0000:65:00.1/sriov_numvfs 
#echo $1 >  /sys/class/net/ens9f0/device/sriov_numvfs

end_time=$($TIME_MILLI)
total_latency=$(($end_time - $start_time))
echo total_latency:${total_latency}ms
