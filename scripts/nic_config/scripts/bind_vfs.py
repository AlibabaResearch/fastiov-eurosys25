import os
import sys
import time
sys.path.append("/root/ipu/scripts")
from ioctl_test import call_bdf_register_ioctl

vf_nums = int(sys.argv[1])

def get_hex(num):
    hex_number = format(num, '02x')
    return hex_number

def get_vf_pcis(device_id_start, vf_num):
    addr_fmt = "0000:e3:{}.{}"
    addrs = []
    for vid in range(vf_num):
        addr1 = get_hex(int(vid/8) + device_id_start)
        addr2 = str(vid%8)
        assert int(vid/8) <= 31
        addr = addr_fmt.format(addr1, addr2)
        addrs.append(addr)
    return addrs

pci_addrs = get_vf_pcis(1, vf_nums)
pci_addrs.extend(get_vf_pcis(17, vf_nums))
t_start = time.time()

# ubind all vfs from host idpf driver

for a_idx, addr in enumerate(pci_addrs):
    print(f"unbind host [{a_idx}] = {addr}")
    os.system("python3 /opt/dpdk-stable-21.11.1/usertools/dpdk-devbind.py -u {}".format(addr))

t_end = time.time()
print(f"unbind time = {t_end - t_start}s")


# no longer needs this after implementing the pcl lock
# for a_idx, addr in enumerate(pci_addrs):
#     print(f"register vfio independent devset [{a_idx}] = {addr}")
#     call_bdf_register_ioctl(addr)

# bind all vfs to vfio_pci driver
for a_idx, addr in enumerate(pci_addrs):
    print(f"bind to vfio [{a_idx}] = {addr}")
    os.system("python3 /opt/dpdk-stable-21.11.1/usertools/dpdk-devbind.py -b vfio-pci {}".format(addr))

print(f"bind time = {time.time() - t_start}s")
