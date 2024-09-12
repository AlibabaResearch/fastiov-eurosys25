#!/bin/bash


usage() {
    cat << EOF
Usage:
./clean.sh -n namespace [-r]
EOF
}


check_http_response() {
  url=$1
  response=$(curl -s -o /dev/null -w "%{http_code}\n%{response_code}" "$url")
  http_code=$(echo "$response" | sed -n '1p')
  server_response=$(echo "$response" | sed -n '2p')
  if [ ! "$http_code" -eq 200 ]; then
    echo "HTTP error: $http_code: $server_response"
  fi
}


while getopts "n:rpf" opt; do
  case ${opt} in
    n )
      ns=${OPTARG}
      ;;
    r )
      doremove=1
      ;;
    p )
      dopkill=1
      ;;
    f )
      dofix=1
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

if [ -z "$ns" ]; then
  echo "Missing required argument: -n" >&2
  usage
  exit 1
fi


echo "Test clean: rm containers"
for container in $(crictl ps -q); do
	#echo $container
	crictl stop $container > /dev/null
	crictl rm -f $container > /dev/null
done


echo "Test clean: rm pods"
for pod in $(crictl pods --namespace $ns -q); do
	#echo $pod
	#crictl stopp $pod > /dev/null
	crictl rmp -f $pod > /dev/null
done
# pkill return status code 1, if no process matched: https://stackoverflow.com/questions/54530278/cant-check-if-pkill-command-is-successful-or-not
pkill "containerd-shim-runc-v2"


echo "Test clean: rm all cni network ns"
namespaces=$(ip netns list | grep -o 'cni-.*')
for ns in $namespaces; do
    ip netns del "$ns"
    echo "Deleted network namespace $ns"
done


echo "Test clean: clean history ipam records"
rm -rf /var/lib/cni/networks/containerd-net/*


if [ ! -z "$doremove" ]; then
  DIR=$(dirname $0)
  kata_log_dir="$DIR/../logs/kata_logs/tmp/*"
  # kata_log_dir2="/tmp/pod_test/kata.log"
  containerd_log_dir="$DIR/../logs/containerd_logs/tmp/*"
  cni_log_dir="$DIR/../logs/cni_logs/tmp/*"
  # cni_log_dir2="/tmp/pod_test/vpccni.log"
  qemu_log_dir="/root/ipu/timeline-kata-qemu/*"
  echo "Test clean: rm tmp logs at [$kata_log_dir] [$containerd_log_dir] [$cni_log_dir] [$qemu_log_dir]"
  rm -rf $kata_log_dir
  rm -rf $containerd_log_dir
  rm -rf $cni_log_dir
  # rm -rf $qemu_log_dir

  cni_conf_cache="/tmp/pod_test/sriov-conf/*"
  echo "Test clean: rm sriov cni netconf caches at [$cni_conf_cache]"
  rm -rf $cni_conf_cache

  echo "Test clean: rm barrier_sem records"
  /root/ipu/scripts/barrier_sem/unlink_sem /barrierVM
fi


if [ ! -z "$dopkill" ]; then
  echo "exiting all closedloop_net scripts..."
  pkill closedloop_net
  pkill -9 closed
fi


if [ ! -z "$dofix" ]; then
  DIR=$(dirname $0)
  echo "fix containerd cleaning bug..."
  bash $DIR/fix_metadb.sh
fi

echo "clean.sh ok"
