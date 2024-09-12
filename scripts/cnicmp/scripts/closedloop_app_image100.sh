#!/bin/bash

usage() {
    cat << EOF
Usage:
./closedloop.sh -c test_concurrency -t test_tenants -i test_iters -p pod_runtime [-r] [-n] [-x]
    -r: remove tmp files
    -n: no network
    -x: no clean
EOF
}

noclean=0
network=1
while getopts "c:t:i:p:rnx" opt; do
  case ${opt} in
    c )
      test_concurrency=${OPTARG}
      ;;
    t )
      test_tenants=${OPTARG}
      ;;
    i )
      test_iters=${OPTARG}
      ;;
    p )
      pod_runtime=${OPTARG}
      ;;
    r )
      remove=1
      ;;
    n )
      network=2
      ;;
    x )
      noclean=1
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

if [ -z "$test_concurrency" ] || [ -z "$test_tenants" ] || [ -z "$test_iters" ] || [ -z "$pod_runtime" ]; then
  echo "Missing required argument: -c, -t, -i, or -p" >&2
  usage
  exit 1
fi

pod_num=$test_concurrency
tnt_num=$test_tenants
req_num=$test_iters
runtime=$pod_runtime
tnt_pod_num=$(( $pod_num / $tnt_num ))

DIR=$(dirname $0)
result_dir=${result_dir:-$(printf "%s_%03d_%03d_%s" ${runtime} ${pod_num} ${tnt_num} $(date +%m%d%H%M))}
ns=${ns:-"test"}
tmp_dir="/tmp/pod_test"
kata_log_dir="$DIR/../logs/kata_logs/tmp"
containerd_log_dir="$DIR/../logs/containerd_logs/tmp"
cni_log_dir="$DIR/../logs/cni_logs/tmp"
log_tool_dir="$DIR/log_tool.py"

clean() {
    echo "Step 1: cleaning pods..."
    if [ ! -z "$remove" ]; then
        timeout 3000 $DIR/clean.sh -n $ns -r
    else
        timeout 3000 $DIR/clean.sh -n $ns
    fi
    if [[ $? != 0 ]]; then
        printf "\nremove pods failed\n" >&2
        exit 1
    fi
}

gen_config() {
    echo "Step 2: gen pod configs..."
    pod_config=()
    container_config=()
    log_file=()
    for pod_idx in $(seq ${pod_num}); do
        local tnt_idx=$(( ($pod_idx - 1) / $tnt_pod_num + 1 ))
        local tnt_pod_idx=$(( ($pod_idx - 1) % $tnt_pod_num + 1 ))
        local p1=$(printf "%03d" ${tnt_idx})
        local p2=$(printf "%03d" ${tnt_pod_idx})
        log_file[$pod_idx]="${result_dir}/_pod_${p1}_${p2}.txt"
        pod_config[$pod_idx]="${tmp_dir}/_pod_config_${p1}_${p2}.yaml"
        cat > ${pod_config[$pod_idx]} << EOF
metadata:
  name: sandbox-${p1}-${p2}
  namespace: $ns
  uid: busybox-sandbox
  attempt: 1
log_directory: $tmp_dir
linux:
  security_context:
    namespace_options:
      network: $network
EOF
        container_config[$pod_idx]="${tmp_dir}/_container_config_${p1}_${p2}.json"
        cat > ${container_config[$pod_idx]} << EOF
{
    "metadata": {
                "name": "image-${p1}-${p2}"            
    },
    "image":{
        "image": "fastiov-benchmark/video"        
    },
        "command": [
          "python3", "/home/compatible-benchmark-code/image/python/function-net2.py", "http://10.88.0.1:5100/download/0_action-adrenaline-adventure-1047051.jpg", "/home/compatible-benchmark-code/test-tmp/input.jpg", "/home/compatible-benchmark-code/test-tmp/test0.jpg", "1000", "1000", "0.01"
        ],
        "log_path":"/0.log",
        "linux": {
		"resources": {
			"cpu_shares": 1024,
      "cpuset_cpus": "$(((pod_idx-1) + 12))"
		}
	}
}
EOF
    done
}

# [image]
# "python3", "/home/compatible-benchmark-code/image/python/function.py", "/home/compatible-benchmark-code/image/data/0_action-adrenaline-adventure-1047051.jpg", "/home/compatible-benchmark-code/test-tmp/test0.jpg", "1000", "1000", "0.01"  
# [video]
# "python3", "/home/compatible-benchmark-code/video/python/function.py", "/home/compatible-benchmark-code/video/data/city.mp4", "/home/compatible-benchmark-code/video/data/test", "1", "watermark", "0.01" 
# [compression]
# "python3", "/home/compatible-benchmark-code/compression/python/function.py", "/home/compatible-benchmark-code/compression/data/acmart-master/", "/home/compatible-benchmark-code/compression/data/", "0.01"
# [inference]
# "python3", "/home/compatible-benchmark-code/inference/python/function.py", "/home/compatible-benchmark-code/inference/data/model/resnet50-19c8e357.pth", "/home/compatible-benchmark-code/inference/data/fake-resnet/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg", "0.01"
# [scientific-graph]
# "python3", "/home/compatible-benchmark-code/scientific/python/function.py", "100000", "0.01"
# "python3", "/home/compatible-benchmark-code/scientific/python/function.py", "/home/compatible-benchmark-code/scientific/data/test.pickle", "500000", "0.01"   

#net download
# [image]
# "python3", "/home/compatible-benchmark-code/image/python/function-net.py", "http://10.88.0.1:5100/download/0_action-adrenaline-adventure-1047051.jpg", "/home/compatible-benchmark-code/test-tmp/input.jpg", "/home/compatible-benchmark-code/test-tmp/test0.jpg", "1000", "1000", "0.01" 
# python3 /home/compatible-benchmark-code/image/python/function-net.py http://10.88.0.1:5100/download/0_action-adrenaline-adventure-1047051.jpg /home/compatible-benchmark-code/test-tmp/input.jpg /home/compatible-benchmark-code/test-tmp/test0.jpg 1000 1000 0.01 
# [video]
# "python3", "/home/compatible-benchmark-code/video/python/function-net.py", "http://10.88.0.1:5100/download/city.mp4", "/home/compatible-benchmark-code/test-tmp/city.mp4", "/home/compatible-benchmark-code/video/data/test", "1", "watermark", "0.01" 
# python3 /home/compatible-benchmark-code/video/python/function-net.py http://10.88.0.1:5100/download/city.mp4 /home/compatible-benchmark-code/test-tmp/city.mp4 /home/compatible-benchmark-code/video/data/test 1 watermark 0.01 
# [compression]
# "python3", "/home/compatible-benchmark-code/compression/python/function-net.py", "http://10.88.0.1:5100/download/acmart.tar", "/home/compatible-benchmark-code/test-tmp/acmart.tar", "/home/compatible-benchmark-code/test-tmp/", "0.01"
# python3 /home/compatible-benchmark-code/compression/python/function-net.py http://10.88.0.1:5100/download/acmart.tar /home/compatible-benchmark-code/test-tmp/acmart.tar /home/compatible-benchmark-code/test-tmp/ 0.01
# [inference]
# "python3", "/home/compatible-benchmark-code/inference/python/function-net.py", "http://10.88.0.1:5100/download/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg", "/home/compatible-benchmark-code/inference/data/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg", "0.01"
# "python3", "/home/compatible-benchmark-code/inference/python/function-net.py", "http://10.88.0.1:5100/download/resnet50-19c8e357.pth", "/home/compatible-benchmark-code/inference/data/resnet50-19c8e357.pth", "http://10.88.0.1:5100/download/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg", "/home/compatible-benchmark-code/inference/data/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg", "0.01"
# python3 /home/compatible-benchmark-code/inference/python/function-net.py http://10.88.0.1:5100/download/resnet50-19c8e357.pth /home/compatible-benchmark-code/inference/data/resnet50-19c8e357.pth http://10.88.0.1:5100/download/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg /home/compatible-benchmark-code/inference/data/512px-Cacatua_moluccensis_-Cincinnati_Zoo-8a.jpg 0.01
# [scientific-graph]
# "python3", "/home/compatible-benchmark-code/scientific/python/function-net.py", "http://10.88.0.1:5100/download/test-graph-10000.pickle", "/home/compatible-benchmark-code/test-tmp/test-graph.pickle", "0.01" 
# python3 /home/compatible-benchmark-code/scientific/python/function-net.py http://10.88.0.1:5100/download/test-graph-10000.pickle /home/compatible-benchmark-code/test-tmp/test-graph.pickle 0.01

TIME_MILLI="date +%s%3N" # in milliseconds
# lyz: change the ready condition - until icmp reply
client() { # client sandbox.yaml output_filename
    local pod_config=$1
    local container_config=$2
    local output=$3

    local start_time=$($TIME_MILLI)
    echo "    start pod with $pod_config"
    pid=$(crictl runp --runtime=$runtime $pod_config)
    while true; do # wait for pod ready
        if (crictl pods | wc -l | grep -q "$test_concurrency") || (crictl inspectp $pid | grep -q "SANDBOX_READY"); then
            break
        else
            sleep 0.1
        fi
    done
    cid=$(crictl create --no-pull $pid $container_config $pod_config)
    crictl start $cid > /tmp/silent

    # while true; do # wait for pod ready
    #     if crictl inspect $cid | grep -q "CONTAINER_EXITED"; then
    #         break
    #     else
    #         sleep 0.01
    #     fi
    # done

    while true; do # wait for pod ready
        if (crictl inspect $cid | grep -q "CONTAINER_EXITED") || (cat /tmp/pod_test/0.log | grep measure | wc -l | grep -q "$test_concurrency") || (cat /tmp/pod_test/0.log | grep measure | wc -l | grep -q "$((test_concurrency-1))"); then
            break
        else
            sleep 0.3
        fi
    done

    
    #crictl inspect $cid | grep reason
    sleep 0.1
    local end_time=$($TIME_MILLI)
    local total_latency=$(($end_time - $start_time))
    echo $pid $start_time $end_time $total_latency >> $output
}

run_once() {
    local pid=()
    for c in $(seq ${pod_num}); do
        fid=$c
	      client ${pod_config[$fid]} ${container_config[$fid]} ${log_file[$c]} &
        pid+=($!)
    done
    wait ${pid[@]}
}

run_multi() {
    echo "Step 3: run tests..."
    for i in $(seq ${req_num}); do
        local datestr=$(date "+%Y%m%d%H%M%S")
        touch ${kata_log_dir}/kata-${datestr}.tf
        touch ${containerd_log_dir}/containerd-${datestr}.tf
        touch ${cni_log_dir}/cni-${datestr}.tf
        echo "cleaning qemu and kernel logs!!!"
        rm -rf /root/ipu/timeline-kata-qemu/*
        dmesg -C
        local iii=$(printf "%03d" $i)
        echo "round $iii starts..."
        local start_time=$($TIME_MILLI)
        echo "$start_time" > /tmp/pod_test/0.log
        run_once
        local end_time=$($TIME_MILLI)
        local total_latency=$(($end_time - $start_time))
        echo "round $iii finishes: $total_latency ms latency"
        echo "collecting logs..."
        sleep 5
        if [ ! -z "$remove" ]; then
	        python3 ${log_tool_dir} --rm
        else
            python3 ${log_tool_dir}
        fi
        qemu_log_dir="$DIR/../logs/qemu_logs/time_qemu_$datestr"
        echo "writing qemu logs to $qemu_log_dir"
        #find /root/ipu/timeline-kata-qemu -type f -name "*.log" -print0 | xargs -0 -I {} sed -i '/vfio-cont-ok/,$d' {}
        #cat /root/ipu/timeline-kata-qemu/* | grep "iova" > $qemu_log_dir

        kernel_log_dir="$DIR/../logs/kernel_logs/time_kernel_$datestr"
        echo "writing kernel logs to $kernel_log_dir"

        local app_log_path="$DIR/../logs/app_logs/app_log_$datestr"
        cp /tmp/pod_test/0.log $app_log_path
        echo "writing app logs to $app_log_path"

        dmesg | grep "vfio"  > $kernel_log_dir
        sleep 0.1
        clean
    done
}

mkdir -p ${tmp_dir}
mkdir -p ${result_dir}
mkdir -p ${kata_log_dir}
mkdir -p ${containerd_log_dir}
mkdir -p ${cni_log_dir}

if [ "$(ls -A ${kata_log_dir})" ]; then
    rm ${kata_log_dir}/*
fi
if [ "$(ls -A ${containerd_log_dir})" ]; then
    rm ${containerd_log_dir}/*
fi

if [ noclean == 0 ]; then
  echo "[Test]-1: clean..."
  clean
fi

echo "[Test]-2: restart containerd..."
systemctl restart containerd

echo "[Test]-3: gen pod condfig..."
gen_config

echo "[Test]-4: run pod test with multiple times..."
run_multi
