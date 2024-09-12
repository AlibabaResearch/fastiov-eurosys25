#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>


SEC("kprobe/vfio_assign_device_set")
int fastiov_custom_vfio_assign_device_set_func(unsigned int bdf, unsigned int *new_set_id_ptr) {
    // Set New dev_set ID and return, TBD: look for the bdf
    if (bdf == 0) {
        return 1;
    }
    *new_set_id_ptr = bdf;
    return 0;
}
