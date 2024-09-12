import os
import sys
import time
import threading

from ioctl_test import call_bdf_register_ioctl


import subprocess

def bind_device_to_vfio2(pci_address):
    # 确保传入的PCI地址格式正确
    if not pci_address.startswith("0000:"):
        pci_address = "0000:" + pci_address

    print(pci_address)
    # if "0000:e3:01.0" in pci_address or "0000:e3:11.0" in pci_address:
    #     return

    # 绑定设备
    try:
        with open(f"/sys/bus/pci/drivers/vfio-pci/bind", "w") as bind_file:
            bind_file.write(pci_address)
    except FileNotFoundError:
        print("无法将设备绑定到vfio-pci驱动。")
        pass
        #raise RuntimeError("无法将设备绑定到vfio-pci驱动。")


def bind_device_to_vfio(pci_address):
    """绑定指定PCI地址的设备到vfio-pci驱动"""

    # 确保传入的PCI地址格式正确
    if not pci_address.startswith("0000:"):
        pci_address = "0000:" + pci_address

    # 设备的sysfs路径
    device_path = f"/sys/bus/pci/devices/{pci_address}"

    # 确保vfio-pci模块已加载
    #subprocess.run("sudo modprobe vfio-pci", shell=True, check=True)

    # 解绑设备
    # try:
    #     with open(f"{device_path}/driver/unbind", "w") as unbind_file:
    #         unbind_file.write(pci_address)
    # except FileNotFoundError:
    #     print(f"设备 {pci_address} 可能已经解绑或不存在相应的驱动。")

    # 读取设备的vendor和device ID
    with open(f"{device_path}/vendor", "r") as vendor_file:
        vendor_id = vendor_file.read().strip()

    with open(f"{device_path}/device", "r") as device_file:
        device_id = device_file.read().strip()

    # 移除前缀 '0x'
    vendor_id = vendor_id[2:]
    device_id = device_id[2:]

    print(f"{vendor_id} {device_id}")

    # 绑定设备
    try:
        with open(f"/sys/bus/pci/drivers/vfio-pci/new_id", "w") as new_id_file:
            new_id_file.write(f"{vendor_id} {device_id}")
    except FileNotFoundError:
        raise RuntimeError("无法将设备绑定到vfio-pci驱动。")


# Function to bind a VF to vfio-pci
def bind_vf_to_vfio_pci(addr):
    bind_command = "python3 /opt/dpdk-stable-21.11.1/usertools/dpdk-devbind.py -b vfio-pci {}".format(addr)
    os.system(bind_command)
    print(f"VF bound to vfio-pci: {addr}")

# Function to handle VF binding in a thread
def thread_bind_vfs_to_vfio_pci(start_index, end_index):
    for i in range(start_index, end_index):
        #bind_vf_to_vfio_pci(pci_addrs[i])
        #print(f"unbind host [{i}] = {pci_addrs[i]}")
        #os.system("python3 /opt/dpdk-stable-21.11.1/usertools/dpdk-devbind.py -u {}".format(pci_addrs[i]))
        bind_device_to_vfio(pci_addrs[i])

# Convert a decimal number to a 2-digit hexadecimal string
def get_hex(num):
    return format(num, '02x')

# Generate PCI addresses for VFs
def get_vf_pcis(device_id_start, vf_num):
    addr_fmt = "0000:e3:{}.{}"
    addrs = []
    for vid in range(vf_num):
        addr1 = get_hex(int(vid / 8) + device_id_start)
        addr2 = str(vid % 8)
        assert int(vid / 8) <= 31
        addr = addr_fmt.format(addr1, addr2)
        addrs.append(addr)
    return addrs

vf_nums = int(sys.argv[1])
thread_count = int(sys.argv[2])  # Number of threads as a command line argument

pci_addrs = get_vf_pcis(1, vf_nums)
pci_addrs.extend(get_vf_pcis(17, vf_nums))

t_start = time.time()

# Register VFIO independent devset for each VF
for a_idx, addr in enumerate(pci_addrs):
    print(f"register vfio independent devset [{a_idx}] = {addr}")
    call_bdf_register_ioctl(addr)

# Calculate the number of VFs each thread should handle
vfs_per_thread = len(pci_addrs) // thread_count
remainder = len(pci_addrs) % thread_count
threads = []

# Create and start threads
start_index = 0
for i in range(thread_count):
    end_index = start_index + vfs_per_thread + (1 if i < remainder else 0)
    thread = threading.Thread(target=thread_bind_vfs_to_vfio_pci, args=(start_index, end_index))
    threads.append(thread)
    thread.start()
    start_index = end_index

# Wait for all threads to complete
for thread in threads:
    thread.join()

print(f"Bind time = {time.time() - t_start}s")
