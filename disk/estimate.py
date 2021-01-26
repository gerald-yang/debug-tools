#! /usr/bin/python2
# @lint-avoid-python-3-compatibility-imports
#
# biolatency    Summarize block device I/O latency as a histogram.
#       For Linux, uses BCC, eBPF.
#
# USAGE: biolatency [-h] [-T] [-Q] [-m] [-D] [interval]
#
# Copyright (c) 2015 Brendan Gregg.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# 20-Sep-2015   Brendan Gregg   Created this.

from __future__ import print_function
from bcc import BPF
from time import sleep, strftime
import argparse
import datetime
import ctypes as ct

log2_index_max = 65

def _print_log2_hist(vals, val_type):
    log2_dist_max = 64
    idx_max = -1
    val_max = 0

    for i, v in enumerate(vals):
        if v > 0: idx_max = i
        if v > val_max: val_max = v

    if idx_max <= 32:
        header = "log :      %-19s : count"
        body = "%3d : %10d -> %-10d : %-8d"
    else:
        header = "log :                %-29s : count"
        body = "%3d : %20d -> %-20d : %-8d"

    if idx_max > 0:
        print(header % val_type)

    for i in range(1, idx_max + 1):
        low = (1 << i) >> 1
        high = (1 << i) - 1
        if (low == high):
            low -= 1
        val = vals[i]

        print(body % (i-1, low, high, val))

def print_log2_hist(dist, val_type="value", section_header="Bucket ptr"):
    if isinstance(dist.Key(), ct.Structure):
        tmp = {}
        f1 = dist.Key._fields_[0][0]
        f2 = dist.Key._fields_[1][0]
        for k, v in dist.items():
            bucket = getattr(k, f1)
            vals = tmp[bucket] = tmp.get(bucket, [0] * log2_index_max)
            slot = getattr(k, f2)
            vals[slot] = v.value
        for bucket, vals in tmp.items():
            print("\n%s = %s" % (section_header, bucket))
            _print_log2_hist(vals, val_type)

# arguments
examples = """examples:
    ./estimate.py                        # summarize block I/O latency as a histogram
    ./esitmate.py 1                      # print 1 second summaries
    ./estimate.py -m 1                   # 1s summaries, milliseconds
    ./estimate.py -m 1 --rootdisk sda    # 1s summaries, milliseconds, exclude sda
"""
parser = argparse.ArgumentParser(
    description="Summarize block device I/O latency as a histogram",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=examples)
parser.add_argument("-m", "--milliseconds", action="store_true",
    help="millisecond histogram")
parser.add_argument("-R", "--rootdisk", default="sdac",
    help="ignore root disk")
parser.add_argument("interval", nargs="?", default=60,
    help="output interval, in seconds")
args = parser.parse_args()
debug = 0

# define BPF program
bpf_text = """
#include <uapi/linux/ptrace.h>
#include <linux/blkdev.h>

typedef struct disk_key {
    char disk[DISK_NAME_LEN];
    u64 slot;
} disk_key_t;
BPF_HASH(start, struct request *);
STORAGE

static int strcmp_workaround(char *name, char *osd_name, int len)
{
    int i;

    for (i = 0; i < len; i++) {
        if (name[i] != osd_name[i])
            return 1;
    }

    return 0;
}

// time block I/O
int trace_req_start(struct pt_regs *ctx, struct request *req)
{
    u64 ts = bpf_ktime_get_ns();
    if (strcmp_workaround(req->rq_disk->disk_name, "ROOTDISK", RDLEN))
        start.update(&req, &ts);
    return 0;
}

// output
int trace_req_completion(struct pt_regs *ctx, struct request *req)
{
    u64 *tsp, delta;

    // fetch timestamp and calculate delta
    tsp = start.lookup(&req);
    if (tsp == 0) {
        return 0;   // missed issue
    }
    delta = bpf_ktime_get_ns() - *tsp;
    FACTOR

    // store as histogram
    disk_key_t key = {.slot = bpf_log2l(delta)};
    // ignore null disk name
    if (req->rq_disk->disk_name[0] != 0) {
        bpf_probe_read(&key.disk, sizeof(key.disk), req->rq_disk->disk_name);
        dist.increment(key);
    }

    start.delete(&req);
    return 0;
}
"""

# code substitutions
if args.milliseconds:
    bpf_text = bpf_text.replace('FACTOR', 'delta /= 1000000;')
    label = "msecs"
else:
    bpf_text = bpf_text.replace('FACTOR', 'delta /= 1000;')
    label = "usecs"

bpf_text = bpf_text.replace('STORAGE',
'BPF_HISTOGRAM(dist, disk_key_t);')

bpf_text = bpf_text.replace("ROOTDISK", args.rootdisk)
bpf_text = bpf_text.replace("RDLEN", str(len(args.rootdisk)))

if debug:
    print(bpf_text)

# load BPF program
b = BPF(text=bpf_text)
b.attach_kprobe(event="blk_start_request", fn_name="trace_req_start")
b.attach_kprobe(event="blk_mq_start_request", fn_name="trace_req_start")
b.attach_kprobe(event="blk_account_io_completion",
    fn_name="trace_req_completion")

print("Tracing block device I/O... Hit Ctrl-C to end.")

# output
exiting = 0 if args.interval else 1
dist = b.get_table("dist")
while (1):
    try:
        sleep(int(args.interval))
    except KeyboardInterrupt:
        exiting = 1

    print()
    print("time: " + datetime.datetime.now())

    #dist.print_log2_hist(label, "disk")
    print_log2_hist(dist, label, "disk")

    dist.clear()

    if exiting:
        exit()
