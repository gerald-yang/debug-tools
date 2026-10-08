#!/usr/bin/env python3
"""Summarise /tmp/results.jsonl (or files given on the command line)."""
import json, sys

files = sys.argv[1:] or ['/tmp/results.jsonl']
rows = []
for fn in files:
    with open(fn) as fh:
        for line in fh:
            line = line.strip()
            if line:
                rows.append(json.loads(line))

hdr = ("%-26s %-10s %9s %9s %11s %11s %7s" %
       ("config", "result", "wall s", "down ms", "peak mbps", "avg mbps", "sent"))
print(hdr)
print("-" * len(hdr))
for r in rows:
    cfg = "%s ch=%d%s%s" % ("TLS" if r['tls'] else "plain", r['channels'],
                            " postcopy" if r.get('postcopy') else "",
                            " autoconv" if r.get('autoconverge') else "")
    if r.get('tls_priority'):
        cfg += " chacha"
    sent = r.get('transferred_bytes') or 0
    wall = r.get('wall_s') or 0
    # avg goodput over the whole run, in megabits/s (10^6), matching QEMU's "mbps"
    avg = sent * 8 / 1e6 / wall if wall else 0
    print("%-26s %-10s %9.2f %9s %11.1f %11.1f %7.1f GiB" % (
        cfg,
        "OK" if r['completed'] else "FAIL",
        wall,
        r.get('downtime_ms'),
        r.get('peak_mbps') or 0,
        avg,
        sent / 2**30))
