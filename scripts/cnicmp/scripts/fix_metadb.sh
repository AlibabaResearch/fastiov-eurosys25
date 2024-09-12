#!/bin/bash

systemctl stop containerd
# old path:
# rm -r /home/t4-fix/containerd/io.containerd.metadata.v1.bolt/ -f
# cp -r /home/t4-fix/io.containerd.metadata.v1.bolt/ /home/t4-fix/containerd/
# remove all including image:
# rm -r /run/containerd/* -f
# rm -r /home/t4/containerd/* -f
rm -r /home/t4/containerd/io.containerd.metadata.v1.bolt/ -f
cp -r /home/t4/io.containerd.metadata.v1.bolt/ /home/t4/containerd/
systemctl restart containerd