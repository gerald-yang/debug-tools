#!/bin/bash

CLANG_VER="15"
curr_kernel=$(uname -r)
install_go="false"

if snap list | grep -q "^go\s"; then
        echo "golang is installed"
else
        echo "golang is not installed, install now"
        sudo snap install go --classic
        go install github.com/cilium/ebpf/cmd/bpf2go@master
        install_go="true"
fi

if dpkg -s clang-"$CLANG_VER" >/dev/null 2>&1; then
        echo "clang-15 is installed"
else
        echo "clang-15 is not installed, install now"
        sudo apt install -y clang-15
fi

if dpkg -s linux-tools-"$curr_kernel" >/dev/null 2>&1; then
        echo "linux-tools-$curr_kernel is installed"
else
        echo "linux-tools-$curr_kernel is not installed, install now"
        sudo apt install -y linux-tools-"$curr_kernel"
fi

if dpkg -s linux-image-unsigned-"$curr_kernel"-dbgsym >/dev/null 2>&1; then
        echo "linux-image-unsigned-$curr_kernel-dbgsym is installed"
else
        echo "linux-image-unsigned-$curr_kernel-dbgsym is not installed, install now"
        sudo apt install -y linux-image-unsigned-"$curr_kernel"-dbgsym
fi

if [ "$install_go" = "true" ]; then
        echo "set $PATH to include ~/go/bin, then run build.sh again"
else
        bpftool btf dump file /usr/lib/debug/boot/vmlinux-"$curr_kernel" format c > vmlinux.h
        GOPACKAGE=main bpf2go -cc clang-"$CLANG_VER" -cflags '-O2 -g -Wall -Werror' -target bpfel bpf tracepoint.c -- -I /home/ubuntu/go/pkg/mod/github.com/cilium/ebpf@v0.11.0/examples/headers
        go build -o vm-exit main.go bpf_bpfel.go
fi

