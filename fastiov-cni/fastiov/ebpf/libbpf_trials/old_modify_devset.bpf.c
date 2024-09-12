#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <linux/pci.h>
#include <linux/vfio.h>
#include <linux/device.h>


SEC("fastiov_custom_vfio_assign_device_set")
int fastiov_custom_vfio_assign_device_set(struct vfio_device *vfio_dev, unsigned int *new_set_id_ptr) {
    // Get PCI Device object from VFIO Device object
    struct pci_dev *pdev;
    char *base_ptr;
    bpf_probe_read(&base_ptr, sizeof(base_ptr), &vfio_dev->dev);
    if (!base_ptr) {
        return 1;
    }
    base_ptr -= (size_t) &((struct pci_dev *)0)->dev;
    bpf_probe_read(&pdev, sizeof(pdev), &base_ptr);
    if (!pdev) {
        return 1;
    }

    // Get BDF from PCI Device object
    struct pci_bus *bus_ptr;
    bpf_probe_read(&bus_ptr, sizeof(bus_ptr), &pdev->bus);
    if (!bus_ptr) {
        return 1;
    }
    unsigned char bus_number, devfn;
    bpf_probe_read(&bus_number, sizeof(bus_number), &bus_ptr->number);
    bpf_probe_read(&devfn, sizeof(devfn), &pdev->devfn); 
    unsigned int bdf = (bus_number << 8) + devfn;

    // Set New dev_set ID and return
    *new_set_id_ptr = bdf;
    return 0;
}