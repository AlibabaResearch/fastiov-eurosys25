#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <linux/ptrace.h>


SEC("kprobe/vfio_gen_device_set_id")
int fastiov_vfio_gen_device_set_id(struct pt_regs *ctx) {
    unsigned long test_set_id = 1234; 
    bpf_printk("set_id = %lu\n", test_set_id);
    return 0;
}

char _license[] SEC("license") = "GPL";
