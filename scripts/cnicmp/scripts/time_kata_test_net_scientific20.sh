#! /bin/bash

while getopts "rnx" opt; do
  case ${opt} in
    r )
      remove_flag="-r"
      ;;
    n )
      no_network_flag="-n"
      ;;
    x )
      no_clean_flag="-x"
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

DIR=$(dirname $0)
source $DIR/time_test20.conf

rm /tmp/pod_test/0.log
echo "" > /tmp/pod_test/kata.log

kata_config="/etc/kata-containers/configuration-qemu-3.toml"
sed -r -i "s/default_memory = [0-9]+/default_memory = 5120/g" $kata_config

start_date=$(date +%m%d%H%M)
mkdir -p "$DIR/../logs"
base_dir="$DIR/../logs/$(printf "time_kata_%s" $start_date)"
mkdir -p ${base_dir}
version="${base_dir}/versions.txt"
uname -r >> $version
containerd --version >> $version
crictl --version >> $version
/opt/kata3/bin/kata-runtime --version >> $version

for test_concurrency in ${concurency[@]}; do
    if [ $(( $test_concurrency % $test_tenants )) -eq 0 ]; then
        echo "--- kata: $test_concurrency concurrency, $test_tenants tenants ---"
        export result_dir=$(printf "%s/con_%03d" $base_dir $test_concurrency)
        $DIR/closedloop_app_scientific20.sh -c $test_concurrency -t $test_tenants -i $test_iters -p kata $remove_flag $no_network_flag $no_clean_flag
        if [[ $? != 0 ]]; then
            exit $?
        fi
    else
        echo "concurrency $test_concurrency can be divided by tenants $test_tenants, skip..."
    fi
done

echo "exiting all closedloop_net scripts..."
pkill closedloop_net
#rm /tmp/pod_test/0.log
