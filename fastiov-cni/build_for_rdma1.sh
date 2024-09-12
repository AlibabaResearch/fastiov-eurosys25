#!/bin/bash

set -e

only_script=0
while getopts "s" opt; do
  case ${opt} in
    s )
      only_script=1
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

REMOTE_SERVER="rdma1"
CNI_BIN_PATH="/opt/cni/bin"
CNICMP_PATH="/home/hdcni/cnicmp/scripts"

echo "******************* Start *******************"

if [[ $only_script != 1 ]]; then
  echo "build sriov-cni..."
  make clean
  make
  echo "build sriov-cni ok"

  echo "install sriov-cni to $REMOTE_SERVER..."
  rsync ./build/sriov $REMOTE_SERVER:$CNI_BIN_PATH
  echo "install sriov-cni to $REMOTE_SERVER ok"

  echo "install fastiov-cni to $REMOTE_SERVER..."
  rsync ./build/fastiov $REMOTE_SERVER:$CNI_BIN_PATH
  echo "install fastiov-cni to $REMOTE_SERVER ok"
fi

echo "install cnicmp scripts to $REMOTE_SERVER..."
rsync ./cnicmp/scripts/* $REMOTE_SERVER:$CNICMP_PATH
echo "install cnicmp scripts to $REMOTE_SERVER ok"

echo "install eBPF programs to $REMOTE_SERVER..."
rsync ./fastiov/ebpf/* $REMOTE_SERVER:/home/hdcni/fastiov/ebpf
echo "install eBPF programs to $REMOTE_SERVER ok"

echo "******************* Done ********************"
