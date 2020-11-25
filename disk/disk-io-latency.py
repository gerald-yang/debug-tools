#!/usr/bin/python
# @lint-avoid-python-3-compatibility-imports
#
# biosnoop  Trace block device I/O and print details including issuing PID.
#       For Linux, uses BCC, eBPF.
#
# This uses in-kernel eBPF maps to cache process details (PID and comm) by I/O
# request, as well as a starting timestamp for calculating I/O latency.
#
# Copyright (c) 2015 Brendan Gregg.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# 16-Sep-2015   Brendan Gregg   Created this.
# 11-Feb-2016   Allan McAleavy  updated for BPF_PERF_OUTPUT

from __future__ import print_function
from bcc import BPF
import ctypes as ct
import re
import argparse

bpf_text="""
#include <uapi/linux/ptrace.h>
#include <linux/blkdev.h>

struct val_t {
    u32 pid;
    char name[TASK_COMM_LEN];
};

struct data_t {
    u32 pid;
    u64 rwflag;
    u64 delta;
    u64 sector;
    u64 len;
    u64 ts;
    char disk_name[DISK_NAME_LEN];
    char name[TASK_COMM_LEN];
};

BPF_HASH(start, struct request *);
BPF_HASH(infobyreq, struct request *, struct val_t);
BPF_PERF_OUTPUT(events);

static int strcmp_workaround(char *name, char *osd_name, int len)
{
    int i;

    for (i = 0; i < len; i++) {
        if (name[i] != osd_name[i])
            return 1;
    }

    return 0;
}

// cache PID and comm by-req
int trace_pid_start(struct pt_regs *ctx, struct request *req)
{
    struct val_t val = {};

    if (bpf_get_current_comm(&val.name, sizeof(val.name)) == 0) {
        if (strcmp_workaround(req->rq_disk->disk_name, "##ROOTDISK##", ##ROOTDISKLEN##)) {
            val.pid = bpf_get_current_pid_tgid();
            infobyreq.update(&req, &val);
        }
    }
    return 0;
}

// time block I/O
int trace_req_start(struct pt_regs *ctx, struct request *req)
{
    u64 ts;

    if (infobyreq.lookup(&req)) {
        ts = bpf_ktime_get_ns();
        start.update(&req, &ts);
    }

    return 0;
}

// output
int trace_req_completion(struct pt_regs *ctx, struct request *req)
{
    u64 *tsp, delta;
    u32 *pidp = 0;
    struct val_t *valp;
    struct data_t data = {};
    u64 ts;

    // fetch timestamp and calculate delta
    tsp = start.lookup(&req);
    if (tsp == 0) {
        // missed tracing issue
        return 0;
    }
    ts = bpf_ktime_get_ns();
    data.delta = ts - *tsp;
    if ((data.delta / 1000000) > ###THRESHOLD###) {
        data.ts = ts / 1000;

        valp = infobyreq.lookup(&req);
        if (valp == 0) {
            data.len = req->__data_len;
            strcpy(data.name, "?");
        } else {
            data.pid = valp->pid;
            data.len = req->__data_len;
            data.sector = req->__sector;
            bpf_probe_read(&data.name, sizeof(data.name), valp->name);
            struct gendisk *rq_disk = req->rq_disk;
            bpf_probe_read(&data.disk_name, sizeof(data.disk_name),
                           rq_disk->disk_name);
        }

/*
 * The following deals with a kernel version change (in mainline 4.7, although
 * it may be backported to earlier kernels) with how block request write flags
 * are tested. We handle both pre- and post-change versions here. Please avoid
 * kernel version tests like this as much as possible: they inflate the code,
 * test, and maintenance burden.
 */
#ifdef REQ_WRITE
        data.rwflag = !!(req->cmd_flags & REQ_WRITE);
#elif defined(REQ_OP_SHIFT)
        data.rwflag = !!((req->cmd_flags >> REQ_OP_SHIFT) == REQ_OP_WRITE);
#else
        data.rwflag = !!((req->cmd_flags & REQ_OP_MASK) == REQ_OP_WRITE);
#endif

        events.perf_submit(ctx, &data, sizeof(data));
    }
    start.delete(&req);
    infobyreq.delete(&req);

    return 0;
}
"""

# create argument parser
parser = argparse.ArgumentParser(description='Record disk latency for all IO requests')
parser.add_argument('--rootdisk', help='root disk to be excluded', default='sdac')
parser.add_argument('--threshold', help='record disk lantecy exceeding threshold(millisecond)', type=long, default='400')
parser.add_argument('--period', help='if disk latency exceeds threshold and keeps for a perfiod of time, log error messages', type=long, default='30')
args = parser.parse_args()

# replace with argument
bpf_text = bpf_text.replace("##ROOTDISK##", args.rootdisk)
bpf_text = bpf_text.replace("##ROOTDISKLEN##", str(len(args.rootdisk)))
bpf_text = bpf_text.replace("###THRESHOLD###", str(args.threshold))

# load BPF program
b = BPF(text=bpf_text, debug=0)
b.attach_kprobe(event="blk_account_io_start", fn_name="trace_pid_start")
b.attach_kprobe(event="blk_start_request", fn_name="trace_req_start")
b.attach_kprobe(event="blk_mq_start_request", fn_name="trace_req_start")
b.attach_kprobe(event="blk_account_io_completion",
    fn_name="trace_req_completion")

TASK_COMM_LEN = 16  # linux/sched.h
DISK_NAME_LEN = 32  # linux/genhd.h

class Data(ct.Structure):
    _fields_ = [
        ("pid", ct.c_ulonglong),
        ("rwflag", ct.c_ulonglong),
        ("delta", ct.c_ulonglong),
        ("sector", ct.c_ulonglong),
        ("len", ct.c_ulonglong),
        ("ts", ct.c_ulonglong),
        ("disk_name", ct.c_char * DISK_NAME_LEN),
        ("name", ct.c_char * TASK_COMM_LEN)
    ]

# header
print("%-14s %-14s %-6s %-7s %-2s %-9s %-7s %7s" % ("TIME(s)", "COMM", "PID",
    "DISK", "T", "SECTOR", "BYTES", "LAT(ms)"))

rwflg = ""
start_ts = 0
prev_ts = 0
delta = 0
high_latency_start = 0
high_latency_curr= 0

# process event
def print_event(cpu, data, size):
    event = ct.cast(data, ct.POINTER(Data)).contents

    val = -1
    global start_ts
    global prev_ts
    global delta
    global args
    global high_latency_start
    global high_latency_curr

    if event.rwflag == 1:
        rwflg = "W"

    if event.rwflag == 0:
        rwflg = "R"

    if not re.match(b'\?', event.name):
        val = event.sector

    if start_ts == 0:
        prev_ts = start_ts

    if start_ts == 1:
        delta = float(delta) + (event.ts - prev_ts)

    print("%-14.9f %-14.14s %-6s %-7s %-2s %-9s %-7s %7.2f" % (
        delta / 1000000, event.name.decode(), event.pid,
        event.disk_name.decode(), rwflg, val,
        event.len, float(event.delta) / 1000000))

    # track high disk latency start and current timestamp in second
    # if it keeps happening every second for a 'period' of time, print disk issue
    # if it doesn't keep happening in 2 seconds, reset counters and start over
    temp_latency = long(delta / 1000000)
    if high_latency_start == 0 or temp_latency > high_latency_curr + 1:
        high_latency_start = temp_latency
        high_latency_curr = temp_latency
    else:
        high_latency_curr = temp_latency
        if (high_latency_curr - high_latency_start) >= args.period:
            print("Error: disk issue")

    #print("%d: %d %d" %(args.period, high_latency_start, high_latency_curr))
    prev_ts = event.ts
    start_ts = 1

# loop with callback to print_event
b["events"].open_perf_buffer(print_event, page_cnt=64)
while 1:
    b.kprobe_poll()
