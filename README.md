## FastIOV: Fast Startup of Passthrough Network I/O Virtualization for Secure Containers

Code for paper "FastIOV: Fast Startup of Passthrough Network I/O Virtualization for Secure Containers" accepted by EuroSys 2025.

### Setup
#### Kata framework
##### Requirements

- OS: centos 7
- Kata
   - Go 1.20.6, GLIBC_2.28
- Containerd
   - Go 1.12.17, GLIBC_2.28
- Others
   - python3, flask 2.3 
##### Install basic framework 
```
tar xf cri-containerd-cni-1.6.13-linux-amd64.tar.gz -C /
tar xf kata-static-3.1.3-x86_64.tar.xz -C /
mv /opt/kata/ /opt/kata3/
ln -sf /opt/kata3/bin/containerd-shim-kata-v2 /usr/local/bin/containerd-shim-kata3-v2
```
##### Install configuration files
```
cd fastiov
cp -r ./configs/containerd/ /etc/
cp -r ./configs/kata-containers /etc/
cp -r ./configs/net.d/ /etc/cni/
cp ./configs/crictl.yaml /etc/crictl.yaml
```
##### Apply fastiov changes
###### Containerd (time logging added)

- Download containerd source code and apply the patch
```
wget https://codeload.github.com/containerd/containerd/zip/refs/heads/release/1.3
unzip containerd-release-1.3.zip
cd containerd-release-1.3
patch -p1 < fastiov/patches/0001-containerd.patch
```

- Complie and install
```
export GO111MODULE=off
make 
cp ./bin/* /usr/local/bin/
```

- Alternative: compile using docker
   - [fastiov-external-link](https://drive.google.com/drive/folders/1oscmHXlAXW4ZFqVGls1sBDtRO01wL9lw?usp=sharing)
```
cd [fastiov-external-link]/images/
docker load -i build2.zip
bash fastiov/patches/build_scripts/build_containerd_centos8.sh 
```
###### Kata runtime

- Download kata source code and apply the patch
```
wget https://codeload.github.com/kata-containers/kata-containers/zip/refs/heads/stable-3.0
unzip kata-containers-stable-3.0.zip
cd kata-containers-stable-3.0
patch -p1 < fastiov/patches/0001-kata.patch
```

- Complie and install
```
make
cp ./containerd-shim-kata-v2 /opt/kata3/bin/
cp ./kata-runtime /opt/kata3/bin/
```

- Alternative: compile using docker
```
cd [fastiov-external-link]/images/
docker load -i build-kata2.zip
bash fastiov/patches/build_scripts/build_kata_centos8.sh 
```
#### FastIOVd

- Download linux kernel source code and apply the patch
```
wget https://codeload.github.com/torvalds/linux/zip/refs/tags/v6.4-rc5
unzip linux-6.4-rc5.zip
cd linux-6.4-rc5
patch -p1 < fastiov/patches/0001-linux.patch
```

- Compile and install
   - Kernel (VFIO + KVM)
```
vim Makefile => modify: EXTRAVERSION = -rc5test
bash build_whole_kernel.sh
reboot
```

   - FastIOV module
```
# after reboot
bash make_fastiov.sh
```
#### FastIOV-cni

- Configure the PCIe address acording to your NIC
```
cd ./fastiov-cni
vim ./fastiov-cni/fastiov/utils/config-utils.go => modify line31: busPrefix     = "" 
```

- Compile and install
```
cd ./fastiov-cni
make clean
make
cp ./build/fastiov /opt/cni/bin/
```
#### QEMU

- Download qemu source code and apply the patch
```
wget https://codeload.github.com/qemu/qemu/zip/refs/tags/v6.2.0
unzip qemu-6.2.0.zip
cd qemu-6.2.0
patch -p1 < fastiov/patches/0001-qemu.patch
```

- Compile and install
```
eval ./configure "$(cat kata.cfg)"
make -j4
cp ./build/qemu-system-x86_64 /opt/kata3/bin/
vim /etc/kata-containers/configuration-qemu-3.toml => modify: path = "/opt/kata3/bin/qemu-system-x86_64" 
```
#### Kata kernel

- Prepare the kernel using tools provided by kata framework and following [the official instructions](https://github.com/kata-containers/kata-containers/tree/main/tools/osbuilder). 
   - Use the kernel version 5.19.2
```
apt-get install libelf-dev
cd ./kata-containers[path to your kata framework]/tools/packaging/kernel
./build-kernel.sh setup 
```

- Apply the patch to the kernel
```
./kata-containers[path to your kata framework]/tools/packaging/kernel/kata-kernel-linux-5.19.2
patch -p1 < [fastiov path]/patches/0001-kata-kernel.patch
```

- Compile and install
```
cd ./kata-containers[path to your kata framework]/tools/packaging/kernel
./build-kernel.sh build
./build-kernel.sh install 
vim /etc/kata-containers/configuration-qemu-3.toml => modify:  kernel="/usr/share/kata-containers/vmlinuz-5.19.2-96"
```
#### Kata image/agent

- Generate a new image that contains the modified agent
```
cd [path to kata-containers]/tools/osbuilder/
USE_DOCKER=true SECCOMP=false ./image-builder/image_builder.sh ./ubuntu_rootfs/
USE_DOCKER=true SECCOMP=false EXTRA_PKGS="kmod netplan.io" ./rootfs-builder/rootfs.sh -r "${PWD}/ubuntu_rootfs" ubuntu
vim /etc/kata-containers/configuration-qemu-3.toml => modify:  kernel="[path to kata-containers]/tools/osbuilder/kata-containers.img"
```
#### Pre-created binaries

- We also provide pre-created QEMU binary, Kata kernel, and Kata Image under the _binaries/_ folder. 
### Quick Start
#### Reload fastiov
```
cd ./kernel-linux/
bash make_fastiov.sh -r
```
#### Configure NIC
```
cd fastiov/all_scripts/nic_config/scripts/
bash alloc_hugepages.sh # we use dpdk script to config the pages
bash create_vfs.sh 100
bash bind_vfs.py 100
```

- *Note: remember to modify the PCI address in _create_vfs.sh_ and _multhd_bind_vfs.py_ according to your specific NIC
#### Start log server 
```
cd fastiov/all_scripts/
bash run_log_server.sh
```
#### Startup test
```
cd fastiov/cnicmp/scripts/
vim time_test.conf  #modify concurrency
bash time_kata_test_net.sh -r
bash clean.sh -n test -r -p -f
```
#### App test

- Load container image
```
cd ./[fastiov-external-link]/images/
ctr -a /run/containerd/containerd.sock --namespace k8s.io image import benchmark_apps.tar
```

- Start storage server (*_make sure to change the Interface to that of your NIC)_
```
cp -r ./[fastiov-external-link]/benchmark_data ./fastiov/all_scripts/cnicmp/scripts/
cd fastiov/all_scripts/cnicmp/scripts
python3 benchmark_server.py
```

- Start concurrent test
```
cd fastiov/cnicmp/scripts/
bash time_kata_test_net_image.sh -r
bash clean.sh -n test -r -p -f
```
#### Baseline (Vanilla SR-IOV)

- Download and compile the original linux-6.4 kernel
- Disable the async driver execution and DMA memory mapping optimization
```
vim /etc/kata-containers/configuration-qemu-3.toml
Modify:
  path = "[path to the binary]/qemu-system-x86_64-noskip"
  kernel = "[path to the kata kernel]/vmlinux-5.19.2-96"
  image = "[path to the kata image]/kata-containers-e810-sync.img"
```

   - *You can directly use the qemu binary, kata kernel and image that we provided in the _fastiov-external-link/binaries/_ folder. They are the unmodified versions, and you can also build them by yourself.
### Binaries and Images <a id="dataset"></a>

- [fastiov-external-link](https://drive.google.com/drive/folders/1oscmHXlAXW4ZFqVGls1sBDtRO01wL9lw?usp=sharing)
#### 