import mmap, time, sys
gib = int(sys.argv[1]); rate_mib = float(sys.argv[2])
size = gib << 30
m = mmap.mmap(-1, size)
# 17 distinct 1 MiB patterns; 17 is coprime with the chunk count so the
# pattern landing on a given offset rotates every pass -> content really changes
CH = [bytes([0x20 + i]) * (1 << 20) for i in range(17)]
for i, o in enumerate(range(0, size, 1 << 20)):
    m[o:o+(1<<20)] = CH[i % 17]
print("prefaulted %d GiB" % gib, flush=True)
off = 0; written = 0; total = 0; t0 = time.time()
while True:
    m[off:off+(1<<20)] = CH[total % 17]
    off += (1 << 20)
    if off >= size: off = 0
    written += 1; total += 1
    expected = written / rate_mib
    actual = time.time() - t0
    if actual < expected:
        time.sleep(expected - actual)
    if written % 4096 == 0:
        el = time.time() - t0
        print("achieved %.1f MiB/s" % (written/el), flush=True)
        written = 0; t0 = time.time()
