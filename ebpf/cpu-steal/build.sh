#!/bin/bash

#bpftool btf dump file /usr/lib/debug/boot/vmlinux-5.4.0-147-generic format c > vmlinux.h
GOPACKAGE=main bpf2go -cc clang-10 -cflags '-O2 -g -Wall -Werror' -target bpfel bpf tracepoint.c -- -I /home/ubuntu/go/pkg/mod/github.com/cilium/ebpf@v0.11.0/examples/headers
go build -o cpu-steal main.go bpf_bpfel.go

