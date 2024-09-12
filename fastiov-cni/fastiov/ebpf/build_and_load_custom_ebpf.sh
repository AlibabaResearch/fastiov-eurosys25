#!/bin/bash

set -e

echo "[1] Cleaning..."
rm -f ./*.o
echo "[1] Cleaning ok"

echo "[1] Compiling the eBPF program..."
clang -O2 -target bpf -c modify_devset.bpf.c -o modify_devset.bpf.o
echo "[1] Compiling the eBPF program ok"

echo "[2] Compiling the eBPF loader..."
gcc -o modify_devset_loader modify_devset_loader.c -l:libbpf.a -lelf -lz
echo "[2] Compiling the eBPF loader ok"


echo "[3] Running the eBPF loader..."
./modify_devset_loader