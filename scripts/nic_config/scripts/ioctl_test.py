from fcntl import ioctl
import struct

_IOC_NRBITS = 8
_IOC_TYPEBITS = 8
_IOC_SIZEBITS = 13
_IOC_DIRBITS = 3

_IOC_NRMASK = ((1 << _IOC_NRBITS) - 1)
_IOC_TYPEMASK = ((1 << _IOC_TYPEBITS) - 1)
_IOC_SIZEMASK = ((1 << _IOC_SIZEBITS) - 1)
_IOC_DIRMASK = ((1 << _IOC_DIRBITS) - 1)

_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = (_IOC_NRSHIFT + _IOC_NRBITS)
_IOC_SIZESHIFT = (_IOC_TYPESHIFT + _IOC_TYPEBITS)
_IOC_DIRSHIFT = (_IOC_SIZESHIFT + _IOC_SIZEBITS)

_IOC_NONE = 1 << _IOC_DIRSHIFT
_IOC_READ = 2 << _IOC_DIRSHIFT
_IOC_WRITE = 4 << _IOC_DIRSHIFT


def _IO(ioctl_type, ioctl_nr):
    return ((ioctl_type) << _IOC_TYPESHIFT) | ((ioctl_nr) << _IOC_NRSHIFT)


vfio_path = '/dev/vfio/vfio'
VFIO_TYPE = ord(';')
VFIO_BASE = 100
VFIO_GET_API_VERSION = _IO(VFIO_TYPE, VFIO_BASE + 0)
VFIO_DEVICE_SET_INDEPENDENT_REGISTER = _IO(VFIO_TYPE, VFIO_BASE + 25)

'''
    input: vf_addr = 0000:ca:00.6 like string
'''
def call_bdf_register_ioctl(vf_addr: str):
    # print(f"***{vf_addr}***")
    bdf_tuple = construct_ioctl_bdf_tuple_struct(vf_addr)
    with open(vfio_path, "wb") as fd:
        try:
            ret = ioctl(fd, VFIO_DEVICE_SET_INDEPENDENT_REGISTER, bdf_tuple)
            print(f"VFIO API = {VFIO_DEVICE_SET_INDEPENDENT_REGISTER}: ret = {ret}")
        except OSError as e:
            print(f"VFIO API = {VFIO_DEVICE_SET_INDEPENDENT_REGISTER}: call failed!!!")


def construct_ioctl_bdf_tuple_struct(bdf_str: str):
    _, bus, devfn = bdf_str.split(':')
    device, function = devfn.split('.')
    return struct.pack("III", int(bus, 16), int(device, 16), int(function))


'''
    return ok: 
        VFIO API Version: 0
'''
def test_vfio_ioctl():
    with open(vfio_path, "wb") as fd:
        try:
            version = ioctl(fd, VFIO_GET_API_VERSION, 0)
            print(f"VFIO API Version: {version}, API = {VFIO_GET_API_VERSION}")
        except OSError as e:
            print(f"IOCTL call failed: {e}")


if __name__ == "__main__":
    # test_vfio_ioctl()
    call_bdf_register_ioctl("0000:cb:00.1")
    

