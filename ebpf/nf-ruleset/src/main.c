#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <bpf/libbpf.h>

#include "common.h"
#include "nfnetlink_rcv_batch.skel.h"

static volatile sig_atomic_t exiting;

static void handle_signal(int sig)
{
    exiting = 1;
}

static int handle_event(void *ctx, void *data, size_t data_sz)
{
    const struct event *ev = data;

    printf("nfnetlink_rcv_batch skb len: %u\n", ev->len);
    return 0;
}

int main(void)
{
    struct ring_buffer *rb = NULL;
    struct nfnetlink_rcv_batch_bpf *skel;
    int err;

    err = libbpf_set_strict_mode(LIBBPF_STRICT_ALL);
    if (err) {
        fprintf(stderr, "failed to enable libbpf strict mode: %d\n", err);
        return 1;
    }

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    skel = nfnetlink_rcv_batch_bpf__open();
    if (!skel) {
        fprintf(stderr, "failed to open BPF skeleton\n");
        return 1;
    }

    err = nfnetlink_rcv_batch_bpf__load(skel);
    if (err) {
        fprintf(stderr, "failed to load BPF skeleton: %d\n", err);
        goto cleanup;
    }

    err = nfnetlink_rcv_batch_bpf__attach(skel);
    if (err) {
        fprintf(stderr, "failed to attach BPF program: %d\n", err);
        goto cleanup;
    }

    rb = ring_buffer__new(bpf_map__fd(skel->maps.events), handle_event, NULL, NULL);
    if (!rb) {
        err = -errno;
        fprintf(stderr, "failed to create ring buffer: %d\n", err);
        goto cleanup;
    }

    printf("Tracking nfnetlink_rcv_batch skb lengths. Press Ctrl+C to exit.\n");

    while (!exiting) {
        err = ring_buffer__poll(rb, 100 /* ms */);
        if (err == -EINTR) {
            err = 0;
            continue;
        }
        if (err < 0) {
            fprintf(stderr, "ring buffer poll failed: %d\n", err);
            goto cleanup;
        }
    }

cleanup:
    ring_buffer__free(rb);
    nfnetlink_rcv_batch_bpf__destroy(skel);
    return err < 0 ? -err : 0;
}
