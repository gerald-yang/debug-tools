#!/bin/bash

if [ -z "$1" ]; then
	echo "please enter clang version"
	exit -1
fi

CLANG_VER="$1"
curr_kernel=$(uname -r)

if snap list | grep -q "^go\s"; then
        echo "golang is installed"
else
        echo "golang is not installed, install now"
        sudo snap install go --classic
        go install github.com/cilium/ebpf/cmd/bpf2go@master
fi

if dpkg -s ubuntu-dbgsym-keyring >/dev/null 2>&1; then
        echo "ubuntu-dbgsym-keyring is installed"
else
        echo "ubuntu-dbgsym-keyring is not installed, install now"
	sudo apt install -y ubuntu-dbgsym-keyring
	echo "Types: deb
URIs: http://ddebs.ubuntu.com/
Suites: $(lsb_release -cs) $(lsb_release -cs)-updates $(lsb_release -cs)-proposed 
Components: main restricted universe multiverse
Signed-by: /usr/share/keyrings/ubuntu-dbgsym-keyring.gpg" | \
	sudo tee -a /etc/apt/sources.list.d/ddebs.sources
	sudo apt update
fi

if dpkg -s clang-"$CLANG_VER" >/dev/null 2>&1; then
        echo "clang-$CLANG_VER is installed"
else
        echo "clang-$CLANG_VER is not installed, install now"
        sudo apt install -y clang-"$CLANG_VER"
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

PATH=$PATH:~/go/bin
bpftool btf dump file /usr/lib/debug/boot/vmlinux-"$curr_kernel" format c > vmlinux.h
GOPACKAGE=main bpf2go -cc clang-"$CLANG_VER" -cflags '-O2 -g -Wall -Werror' -target bpfel bpf tracepoint.c -- -I /home/ubuntu/go/pkg/mod/github.com/cilium/ebpf@v0.11.0/examples/headers
go build -o vm-exit main.go bpf_bpfel.go

