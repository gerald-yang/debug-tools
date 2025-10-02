// SPDX-License-Identifier: Dual BSD/GPL
// Kprobe program that reports skb->len for nfnetlink_rcv_batch calls.
#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_core_read.h>
#include <bpf/bpf_tracing.h>

#include "common.h"

struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 1 << 24);
} events SEC(".maps");

SEC("kprobe/nfnetlink_rcv_batch+0x2f4")
int handle_nfnetlink_rcv_batch_2f4(struct pt_regs *ctx)
{
    struct event *ev;
    struct sk_buff *skb = (struct sk_buff *)ctx->regs[20];

    if (!skb)
        return 0;

    ev = bpf_ringbuf_reserve(&events, sizeof(*ev), 0);
    if (!ev)
        return 0;

    ev->len = BPF_CORE_READ(skb, len);
    bpf_ringbuf_submit(ev, 0);
    return 0;
}

char LICENSE[] SEC("license") = "Dual BSD/GPL";
