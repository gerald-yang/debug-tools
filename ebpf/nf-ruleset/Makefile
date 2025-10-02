OUTPUT ?= build
BPFOBJ := $(OUTPUT)/nfnetlink_rcv_batch.bpf.o
BPF_SKEL := $(OUTPUT)/nfnetlink_rcv_batch.skel.h
VMLINUX := src/vmlinux.h
USER_OBJ := $(OUTPUT)/nfnetlink_rcv_batch

BPF_CLANG ?= clang
BPFTOOL ?= /usr/lib/linux-tools-6.8.0-85/bpftool
CLANG ?= clang
ARCH ?= $(shell uname -m)

LIBBPF_CFLAGS ?= $(shell pkg-config --cflags libbpf 2>/dev/null)
LIBBPF_LIBS ?= $(shell pkg-config --libs libbpf 2>/dev/null || echo "-lbpf -lelf -lz")

ifeq ($(ARCH),x86_64)
BPF_TARGET := bpfel
BPF_ARCH := x86
else ifeq ($(ARCH),aarch64)
BPF_TARGET := bpfel
BPF_ARCH := arm64
else ifeq ($(ARCH),arm64)
BPF_TARGET := bpfel
BPF_ARCH := arm64
else
BPF_TARGET := bpfeb
BPF_ARCH := $(ARCH)
endif

BPF_CFLAGS := \
	-O2 -g -target bpf -D__TARGET_ARCH_$(BPF_ARCH) \
	-I$(OUTPUT) -Isrc -Wno-unused-value -Wno-pointer-sign \
	-Wno-compare-distinct-pointer-types $(LIBBPF_CFLAGS)

all: $(USER_OBJ)

$(OUTPUT):
	@mkdir -p $(OUTPUT)

$(BPFOBJ): src/nfnetlink_rcv_batch.bpf.c src/common.h $(VMLINUX) | $(OUTPUT)
	$(BPF_CLANG) $(BPF_CFLAGS) -c $< -o $@

$(BPF_SKEL): $(BPFOBJ)
	$(BPFTOOL) gen skeleton $< > $@

$(USER_OBJ): src/main.c src/common.h $(BPF_SKEL) | $(OUTPUT)
	$(CLANG) -O2 -g -I$(OUTPUT) -Isrc $(LIBBPF_CFLAGS) $< -o $@ $(LIBBPF_LIBS)

.PHONY: clean
clean:
	rm -rf $(OUTPUT)
