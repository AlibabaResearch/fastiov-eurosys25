#include <bpf/libbpf.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>


static struct bpf_object *ebpf_obj = NULL;
static struct bpf_program *ebpf_prog = NULL;
static struct bpf_link *ebpf_link = NULL;
static char ebpf_obj_path[] = "./modify_devset.bpf.o";
static char kprobe_path[] = "kprobe/vfio_assign_device_set";
static char kprobe_func_name[] = "fastiov_vfio_gen_device_set_id";


void exit_bpf() {
    if (ebpf_link) {
        bpf_link__destroy(ebpf_link);
    }
    if (ebpf_obj) {
        bpf_object__close(ebpf_obj);
    }
    printf("eBPF program deattached and closed.\n");
}


void sigint_handler(int sig) {
    exit_bpf();
    exit(0);
}


int main(int argc, char **argv) {
    int err;

    signal(SIGINT, sigint_handler);

    // Open and verify eBPF program
    ebpf_obj = bpf_object__open(ebpf_obj_path);
    if (!ebpf_obj) {
        fprintf(stderr, "Failed to open BPF object\n");
        exit_bpf();
        return err;
    }

    // Load eBPF program into the kernel
    err = bpf_object__load(ebpf_obj);
    if (err) {
        fprintf(stderr, "Failed to load BPF object: %d\n", err);
        exit_bpf();
        return err;
    }

    // Attach BPF program to kprobe
    ebpf_prog = bpf_object__find_program_by_name(ebpf_obj, kprobe_func_name);
    if (!ebpf_prog) {
        fprintf(stderr, "Failed to find BPF program\n");
        exit_bpf();
        return -1;
    }

    ebpf_link = bpf_program__attach(ebpf_prog);
    if (!ebpf_link) {
        fprintf(stderr, "Failed to attach BPF program\n");
        exit_bpf();
        return -1;
    }

    printf("Custom eBPF program (%s) opened, loaded and attached to func %s with name %s\n", ebpf_obj, kprobe_path, kprobe_func_name);

    while (1) {
        pause();
    }

    return 0;
}