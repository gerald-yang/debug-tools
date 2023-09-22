//go:build ignore

#include "common.h"

char __license[] SEC("license") = "Dual MIT/GPL";

struct bpf_map_def SEC("maps") counting_map = {
	.type        = BPF_MAP_TYPE_PERCPU_ARRAY,
	.key_size    = sizeof(u32),
	.value_size  = sizeof(u64),
	.max_entries = 100,
};

struct exit_info {
	/* The first 8 bytes is not allowed to read */
	unsigned long pad;

        unsigned int exit_reason;
        unsigned long guest_rip;
        u32 isa;
        u64 info1;
        u64 info2;
        unsigned int vcpu_id;
};

SEC("tracepoint/kvm/kvm_exit")
int tp_kvm_exit(struct exit_info *info) {
	u32 key     = (u32)info->exit_reason;
	u64 initval = 1, *valp;

	valp = bpf_map_lookup_elem(&counting_map, &key);
	if (!valp) {
		bpf_map_update_elem(&counting_map, &key, &initval, BPF_ANY);
		return 0;
	}
	__sync_fetch_and_add(valp, 1);
	return 0;
}
