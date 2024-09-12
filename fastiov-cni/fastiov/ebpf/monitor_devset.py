from bcc import BPF


monitor_prog = """
#include <linux/ptrace.h>
#include <linux/device.h>
#include <linux/vfio.h>
#include <linux/pci.h>


struct devset_info_t {
    u64 set_id;
    u8 bus;
    u8 devfn;
};

BPF_PERF_OUTPUT(devset_events);

int kprobe_monitor_vfio_assign_device_set(struct pt_regs *ctx) {    
    struct devset_info_t devset_info = {};

    // Get set_id
    devset_info.set_id = (u64)PT_REGS_PARM2(ctx);    

    // Get VFIO and PCI Device object
    struct vfio_device *vfio_dev = (struct vfio_device *)PT_REGS_PARM1(ctx);
    struct pci_dev *pdev;
    char *base_ptr;
    bpf_probe_read(&base_ptr, sizeof(base_ptr), &vfio_dev->dev);
    base_ptr -= (size_t) &((struct pci_dev *)0)->dev;
    bpf_probe_read(&pdev, sizeof(pdev), &base_ptr);

    // Get BDF information
    if (pdev) {
        // bpf_trace_printk("kprobe_monitor_vfio_assign_device_set pdev not empty!!!\\n");
        
        struct pci_bus *bus_ptr;
        bpf_probe_read(&bus_ptr, sizeof(bus_ptr), &pdev->bus);
        
        if (bus_ptr) {
            unsigned char bus_number;
            bpf_probe_read(&bus_number, sizeof(bus_number), &bus_ptr->number);
            
            unsigned short devfn;
            bpf_probe_read(&devfn, sizeof(devfn), &pdev->devfn);
            
            u64 bdf = (bus_number << 8) + devfn;

            bpf_trace_printk("kprobe_monitor_vfio_assign_device_set bus_ptr not empty!!! b=%x,df=%x,bdf=%x\\n", bus_number, devfn, bdf);
            
            devset_info.bus = bus_number;
            devset_info.devfn = devfn;
        }
    }

    // Output
    devset_events.perf_submit(ctx, &devset_info, sizeof(devset_info));
    
    return 0;
}
"""


def main():
    b = BPF(text=monitor_prog)
    
    def monitor_devset(cpu, data, size):
        event = b["devset_events"].event(data)
        d = ((event.devfn) >> 3) & 0x1f
        f = event.devfn & 0x07
        print("[vfio_assign_device_set] BDF: %02x:%02x.%x, set_id: %lu" % (event.bus, d, f, event.set_id))

    b.attach_kprobe(event="vfio_assign_device_set", fn_name="kprobe_monitor_vfio_assign_device_set")
    b["devset_events"].open_perf_buffer(monitor_devset)

    print("eBPF monitoring program loaded. Listening to vfio_assign_device_set calls...")

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