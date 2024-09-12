from bcc import BPF


modify_prog = """
#include <linux/ptrace.h>
#include <linux/device.h>
#include <linux/vfio.h>
#include <linux/pci.h>


static u16 extract_bdf_from_vfio_dev(struct vfio_device *vfio_dev) {
    // Get PCI Device object
    struct pci_dev *pdev;
    char *base_ptr;
    bpf_probe_read(&base_ptr, sizeof(base_ptr), &vfio_dev->dev);
    base_ptr -= (size_t) &((struct pci_dev *)0)->dev;
    bpf_probe_read(&pdev, sizeof(pdev), &base_ptr);

    // Get BDF information
    if (pdev) {        
        struct pci_bus *bus_ptr;
        bpf_probe_read(&bus_ptr, sizeof(bus_ptr), &pdev->bus);
        
        if (bus_ptr) {
            unsigned char bus_number;
            bpf_probe_read(&bus_number, sizeof(bus_number), &bus_ptr->number);
            
            unsigned short devfn;
            bpf_probe_read(&devfn, sizeof(devfn), &pdev->devfn);
            
            u16 bdf = (bus_number << 8) + devfn;
            return bdf;
        }
    }
    
    return 0;
}

int kprobe_modify_vfio_gen_device_set_id(struct pt_regs *ctx) {
    u16 bdf = extract_bdf_from_vfio_dev((struct vfio_device *)PT_REGS_PARM1(ctx));
    u64 set_id = (u64)PT_REGS_PARM2(ctx);

    bpf_trace_printk("attach to vfio_gen_device_set_id ok!!! bdf=%x, set_id=%lu", bdf, set_id);
    // bpf_override_return(ctx, test_set_id);
    return 0;
}
"""

modify_prog_simple = """
#include <linux/ptrace.h>

int kprobe_modify_vfio_gen_device_set_id(struct pt_regs *ctx) {
    bpf_trace_printk("attach to vfio_gen_device_set_id ok!!!");
    return 0;
}
"""


def main():
    kprobe_func = "vfio_gen_device_set_id"
    # kprobe_func = "vfio_assign_device_set"
    
    b = BPF(text=modify_prog_simple, debug=0x4)
    
    b.attach_kprobe(event=kprobe_func, fn_name="kprobe_modify_vfio_gen_device_set_id")

    print(f"eBPF program loaded. Listening to {kprobe_func} calls...")

    while True:
        try:
            b.perf_buffer_poll()
        except KeyboardInterrupt:
            break

    print("Detaching eBPF program...")
    b.cleanup()
    print("eBPF program detached.")


if __name__ == "__main__":
    main()