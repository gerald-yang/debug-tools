# TLS live-migration reproduction kit — case 447246

Reproduces the OpenStack live-migration timeout caused by QEMU-native TLS
throttling the migration stream, using **two raw QEMU processes on one host**
migrating over loopback. No OpenStack, no libvirt, no second machine, no
network variable.

Validated on: Ubuntu 24.04, QEMU 8.2.2, kernel 6.8, Xeon Gold 6430 (128 cores,
503 GB RAM), guest 48 vCPU / 192 GiB.

```
gencerts.sh         generate the x509 CA + server/client certs into /tmp/pki
launch-vm.sh        start one QEMU instance (source or destination)
migrate.py          drive one migration over QMP and report metrics
dirtier.py          generate a precise, known memory dirty rate inside the guest
con.py              scripted shell access over the QEMU serial console
sweep-channels.sh   run a multifd channel-count sweep
run-matrix.sh       run an arbitrary list of migration configs back-to-back
vm-status.py        show every test VM and whether it is usable as src/dest
guest-load.sh       start/stop/verify the in-guest dirtier
cleanup.sh          stop and remove all test VMs
repair-disk.sh      offline fsck of the guest image (dead-console recovery)
summarise.py        turn /tmp/results.jsonl into a comparison table
```

---

## 0. Why single-host loopback

Both QEMU processes open the same qcow2 (`file.locking=off`), so there is no
disk copy — only RAM is transferred. The destination allocates its own RAM and
receives pages over a TCP socket on `127.0.0.1`.

Requirements:

* **2x guest RAM free on the host** (source + destination both hold the full
  guest footprint during migration).
* Identical `-machine` / `-cpu` / `-m` / `-smp` on both sides.
* `file.locking=off` on the disk. Safe **only** because exactly one side is
  executing the guest at any instant. Never do this with two genuinely live VMs.

Loopback is unrealistically fast as a *network* baseline — which is exactly
what makes it the right tool here. It removes the NIC as a bottleneck so the
**encryption ceiling is the only thing left to measure**.

---

## 1. Running a live migration

### 1.1 One-time setup

```bash
# host packages
sudo apt-get install -y qemu-system-x86 python3 openssl

# TLS certificates -> /tmp/pki
#   CN=localhost, SAN = DNS:localhost + IP:127.0.0.1
#   so --tls-hostname must stay 'localhost'
sudo ./gencerts.sh
```

You need a bootable qcow2. Default path is `/home/ubuntu/testvm.img`; override
with `DISK=...`. A cloud image works; make sure you have console login
credentials (cloud-init `password:` + `ssh_pwauth: true`).

### 1.2 Start the source VM

```bash
sudo ./launch-vm.sh A 2222
```

Prints the pid, QMP socket `/tmp/A.qmp`, console socket `/tmp/conA.sock`, and
stderr log `/tmp/A.log`.

> **Always read `/tmp/<NAME>.log` after any failure.** QEMU reports migration
> errors (`Cannot read from TLS channel`, assertion failures, section-footer
> errors) there and nowhere else.

### 1.3 Start the destination VM

Destinations need `-incoming defer`, which lets you set capabilities and TLS
parameters *before* the incoming connection is accepted.

```bash
# plaintext destination
sudo ./launch-vm.sh B 2223 "" inc

# TLS destination
sudo ./launch-vm.sh B 2223 tls inc
```

A destination can only be used **once**. After a failed or completed migration
its incoming state is spent — kill it and launch a fresh one. Symptom of
reusing one: `Multifd must be set before incoming starts`.

### 1.4 Run the migration

```bash
# plaintext baseline
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --timeout 300 --json /tmp/results.jsonl

# TLS
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --tls --timeout 300 --json /tmp/results.jsonl

# TLS + multifd, 6 channels
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --tls --channels 6 --timeout 300 --json /tmp/results.jsonl

# TLS + post-copy
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --tls --postcopy --timeout 300 --json /tmp/results.jsonl

# TLS + auto-converge with tuned throttling
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --tls --autoconverge --throttle-initial 50 --throttle-increment 25 \
     --timeout 420 --json /tmp/results.jsonl
```

Exit code is 0 only on `completed`.

After a **successful** migration the guest is running on the destination.
That VM is now your source for the next test; kill the old source by pidfile:

```bash
sudo kill -9 $(sudo cat /tmp/A.pid)
```

### 1.4a Checking what is already running

```bash
sudo ./vm-status.py
```

```
VM     PID      STATE           MIGRATE        ROLE                             FLAGS
-------------------------------------------------------------------------------------
A      23494    postmigrate     completed      SPENT  (guest migrated away)     ssh=2222
B      23555    running         completed      SOURCE (received a guest)        incoming tls ssh=2223
```

| STATE | meaning | usable as |
|---|---|---|
| `running` | guest is executing here | **source** |
| `inmigrate` | armed with `-incoming`, no guest yet | **destination** |
| `postmigrate` | guest already migrated away | nothing — kill it |
| `paused` | stopped, often a failed cutover | nothing — check the log |
| `DEAD` | pidfile/socket exist but process is gone | nothing — `rm /tmp/<NAME>.*` |
| `BUSY` | QMP socket held by another client | a migration is in progress |

Manual equivalents if you prefer:

```bash
# is it alive?
sudo cat /tmp/A.pid && ps -p $(sudo cat /tmp/A.pid) -o pid,etime,args

# what state?
sudo python3 -c "import sys;sys.path.insert(0,'.')
from migrate import QMP
q=QMP('/tmp/A.qmp')
print(q.cmd('query-status'), q.cmd('query-migrate').get('status'))"

# everything at once
ps -eo pid,etime,args | grep '[-]name vm'
ls -la /tmp/*.qmp /tmp/*.pid
sudo cat /tmp/A.log              # QEMU stderr - the only place errors appear
```

Do **not** identify VMs with `pgrep -f "name vmA"` / `pkill -f` — the pattern
matches the invoking shell's own command line. Always use the pidfiles.

### 1.4b Running multiple migrations (IMPORTANT)

**A destination VM is single-use.** Re-running the same `migrate.py` command a
second time against the same pair of VMs will always fail. After run #1:

| VM | `query-status` | why it can't be reused |
|---|---|---|
| source `A` | `postmigrate` | the guest left; A no longer runs anything |
| dest `B` | `running` | B now *is* the guest; its incoming slot is spent |

Typical errors from doing this: `Multifd must be set before incoming starts`,
`attempt to add duplicate property`, `Address already in use`, or a migration
that sits in `setup` forever. `migrate.py` now detects both cases up front and
exits with an explanation instead.

**The correct loop for each additional run is:**

1. the previous **destination becomes the new source**
2. kill the previous source by pidfile
3. launch a **brand-new destination** (fresh name, fresh SSH fwd port)
4. use a **new migration port**

```bash
# run 1:  A -> B
sudo ./launch-vm.sh B 2223 tls inc
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 --tls
sudo kill -9 $(sudo cat /tmp/A.pid)          # A is spent

# run 2:  B -> C     (new dest, new ports)
sudo ./launch-vm.sh C 2224 tls inc
sudo python3 -u ./migrate.py --src /tmp/B.qmp --dst /tmp/C.qmp --port 4445 --tls --channels 6
sudo kill -9 $(sudo cat /tmp/B.pid)
```

If a run **fails**, the guest stays on the source — so keep the source, and
only discard the half-used destination:

```bash
sudo kill -9 $(sudo cat /tmp/C.pid); rm -f /tmp/C.pid
sudo ./launch-vm.sh C2 2225 tls inc          # fresh destination, try again
```

**Or just let `run-matrix.sh` do all of it:**

```bash
sudo ./launch-vm.sh A 2222                   # one source; load it per section 3
sudo ./run-matrix.sh A 4500 \
     ""                     \
     "--tls"                \
     "--tls --channels 4"   \
     "--tls --channels 6"   \
     "--tls --channels 8"   \
     "--tls --postcopy"
```

It allocates names and ports, launches a correctly-configured destination for
each case (TLS iff the options contain `--tls`), chains the guest forward on
success, stops on the first failure leaving the guest alive, and prints the
comparison table at the end.

Set `TIMEOUT=600 RESULTS=/tmp/run2.jsonl` in the environment to override.

### 1.5 The raw QMP sequence (what `migrate.py` actually does)

Useful if you want to drive it by hand or translate to another tool.

**Destination:**
```json
{"execute":"migrate-set-parameters","arguments":{"tls-creds":"tls0","tls-hostname":"localhost"}}
{"execute":"migrate-set-capabilities","arguments":{"capabilities":[
    {"capability":"multifd","state":true},
    {"capability":"postcopy-ram","state":false},
    {"capability":"auto-converge","state":false}]}}
{"execute":"migrate-set-parameters","arguments":{"multifd-channels":6}}
{"execute":"migrate-incoming","arguments":{"uri":"tcp:127.0.0.1:4444"}}
```

**Source:**
```json
{"execute":"object-add","arguments":{"qom-type":"tls-creds-x509","id":"tlscli",
    "dir":"/tmp/pki","endpoint":"client","verify-peer":true}}
{"execute":"migrate-set-parameters","arguments":{
    "max-bandwidth":0,"downtime-limit":300,
    "tls-creds":"tlscli","tls-hostname":"localhost","multifd-channels":6}}
{"execute":"migrate-set-capabilities","arguments":{"capabilities":[...same...]}}
{"execute":"migrate","arguments":{"uri":"tcp:127.0.0.1:4444"}}
{"execute":"query-migrate"}
```

### 1.6 Five traps that will silently invalidate your results

1. **`max-bandwidth` defaults to 128 MiB/s.** Set it to `0`. Without this every
   measurement is just the rate limiter.
2. **Capabilities persist across migrations on the same QEMU instance.** Set
   every capability explicitly to `true` *and* `false` each run, or a previous
   test's multifd/post-copy setting leaks into the next one.
3. **`tls-creds` also persists.** Set it to `""` for a plaintext run on a QEMU
   that previously did TLS, or your "plaintext" baseline is silently encrypted.
4. **`multifd-channels` must be set before `migrate-incoming`** on the
   destination.
5. **An idle guest migrates in seconds no matter what you configure.** If the
   in-guest dirtier is not actually running, *every* configuration looks fast
   and TLS looks harmless. Always confirm the load before you migrate —
   see §3.1a. Pass `--expect-rss-gib <GiB>` to `migrate.py` and it will refuse
   to run at all against an idle guest.

### 1.7 Safety rules learned the hard way

* **Never `migrate_cancel` during `postcopy-active` or `postcopy-paused`.**
  It trips `runstate_set: Assertion 'new_state < RUN_STATE__MAX' failed`,
  QEMU aborts, and the guest is destroyed. `migrate.py` refuses to do this.
* A `postcopy-paused` migration **is** recoverable — on a *new* port:
  ```python
  dst.cmd('migrate-recover', uri='tcp:127.0.0.1:4470')
  src.cmd('migrate', uri='tcp:127.0.0.1:4470', resume=True)
  ```
  Measured: resumed and completed in 45 s. But only if you have not cancelled.
* Kill QEMU by **pidfile**, never by name. `pkill -f "name vmX"` matches its
  own `bash -c` command line and kills the calling shell.

---

## 2. Configuring the number of multifd channels

Three layers, same underlying knob.

### 2.1 QEMU / QMP (what this kit uses)

```
capability   multifd            = true
parameter    multifd-channels   = N      (default 2; only used when multifd is on)
```

Must be set on **both** source and destination, to the **same value**, and on
the destination **before** `migrate-incoming`.

```bash
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --tls --channels 6
```

Verify it took effect:
```bash
sudo python3 -c "
import sys; sys.path.insert(0,'.')
from migrate import QMP
q = QMP('/tmp/A.qmp')
p = q.cmd('query-migrate-parameters')
print('channels :', p['multifd-channels'])
print('tls-creds:', repr(p.get('tls-creds')))
print('max-bw   :', p['max-bandwidth'])
print([c for c in q.cmd('query-migrate-capabilities') if c['state']])
"
```

### 2.2 Sweeping channel counts

```bash
# start a source VM, put load on it (section 3), then:
sudo ./sweep-channels.sh A 4500 1 2 4 6 8 12 16
sudo python3 ./summarise.py /tmp/results.jsonl
```

Chains each destination into the next source and stops at the first failure,
leaving the guest alive on the last good VM.

### 2.3 libvirt

```xml
<!-- virsh migrate --parallel --parallel-connections N -->
```
```bash
virsh migrate --live --parallel --parallel-connections 6 \
      --tls testvm qemu+ssh://dest/system
```

### 2.4 OpenStack Nova

```ini
[libvirt]
live_migration_parallel_connections = 6
live_migration_with_native_tls = true
```

**Available from Nova 33.0.0 / OpenStack 2026.1 "Gazpacho" only.** Not present
in 2024.1 Caracal, 2024.2, 2025.1, or 2025.2. Default `1` (disabled).

Nova refuses `live_migration_parallel_connections > 1` together with
`live_migration_permit_post_copy = true` unless QEMU >= 10.1.0
(`MIN_MULTIFD_WITH_POSTCOPY_QEMU_VERSION`).

Nova's own docs warn each connection can consume a full CPU core, especially
with native TLS — reserve capacity via `[compute] cpu_shared_set` /
`cpu_dedicated_set` / `[DEFAULT] reserved_host_cpus`.

---

## 3. Generating a known dirty rate

**This is the single most important part of the experiment.** An idle guest is
almost all zero pages and migrates in seconds regardless of TLS, proving
nothing. You must pick a dirty rate `D` such that:

```
TLS_throughput  <  D  <  plaintext_throughput
```

Then plaintext converges and TLS does not — which *is* the customer's bug.
Measured on this host: TLS ~5.2 Gbps (~650 MiB/s), plaintext ~22 Gbps
(~2750 MiB/s). `D = 1500 MiB/s` (= 12.6 Gbps) sits cleanly between them.

### 3.1 Using guest-load.sh (recommended)

`dirtier.py` runs **inside the guest**, not on the host. It is delivered over
the **serial console**, because a libvirt-built image usually has the wrong NIC
name under raw QEMU and therefore no network (see the note at the end of this
section).

```bash
# VM name 'A' -> console /tmp/conA.sock
sudo ./guest-load.sh A start 24 1500      # 24 GiB working set, 1500 MiB/s
sudo ./guest-load.sh A status             # what the guest reports
sudo ./guest-load.sh A verify             # independent host-side measurement
sudo ./guest-load.sh A stop
```

`start` uploads the script, kills any previous instance, launches it detached
with `setsid nohup` (so it survives the console session closing), then **gates
on host-side proof that the guest really faulted in the working set** before
reporting success. If the console command silently fails, `start` fails too —
it will not let you migrate an idle guest and believe you measured a dirty one.

### 3.1a Always confirm the load before you migrate

This is the single most common way to get a meaningless result: the dirtier
never started, so the guest is idle, the migration finishes in ~9 s, and TLS
looks harmless. **Verify from the host**, which works even when the guest's
serial console is wedged:

```bash
sudo ./guest-load.sh B status
```

```
=== host-side (authoritative) ===
  vmB pid      : 29733
  guest RSS      : 3.78 GiB   <- must be >= working set
  CPU ticks/3s   : 0   <- >100 = dirtying, ~0 = IDLE
```

Three independent host-side signals, none of which need guest access:

| Signal | Idle guest | Dirtying at 1500 MiB/s |
|---|---|---|
| QEMU RSS (`ps -o rss=`) | ~3.8 GiB | ≥ working set (e.g. 24 GiB) |
| CPU ticks per 3 s | ~0 | > 100 (dirtier pegs ~1 core) |
| `transferred_bytes` in the result | ~4 GiB, `rounds: 3` | ≫ guest RAM touched |

Belt and braces — make `migrate.py` refuse outright:

```bash
sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --expect-rss-gib 24 --timeout 300 --json /tmp/results.jsonl
```

```
FATAL: source guest has only 3.78 GiB resident, expected ~24 GiB.
  The in-guest load is NOT running -- this migration would measure an idle
  guest and finish deceptively fast.
```

**Serial console caveat:** every `con.py` connection hangs up the guest's
`serial-getty@ttyS0`. Several rapid connections can trip systemd's restart
limit (5 starts / 10 s), after which the console goes permanently silent even
though the guest is healthy. `con.py` now retries with a 5 s backoff, and
`guest-load.sh start` uses a **single** console session. If the console does
wedge, the host-side numbers above still tell you everything; recovering the
console itself requires restarting the VM.

**The load survives migration.** The dirtier is an ordinary process inside the
guest, so it migrates along with it. Start it **once** on your first source VM
and it keeps running through every hop of the matrix — just use the *current*
VM's name when you query it:

```bash
sudo ./launch-vm.sh A 2222
sudo ./guest-load.sh A start 24 1500      # start the load ONCE

sudo ./run-matrix.sh A 4500 "" "--tls" "--tls --channels 6"
# ... guest ends up on vmD3 ...

sudo ./guest-load.sh D3 status            # still running, same rate
```

Start the load **before** the migration and leave it running for the whole run.
Never start it mid-migration: the dirty rate would change partway through and
the result would be uninterpretable.

### 3.2 Choosing the numbers

`guest-load.sh <VM> start <WORKING_SET_GiB> <RATE_MiB_s>`

* **working set** must fit comfortably in guest RAM (it is mmap'd and fully
  prefaulted). 24 GiB inside a 192 GiB guest is a good ratio. Too small and it
  barely perturbs convergence; too large and the first pass dominates the test.
* **rate** must sit between the two throughput ceilings. Convert to Gbps to
  compare against migration throughput: `MiB/s x 8 x 1048576 / 1e9`, so
  1500 MiB/s = **12.6 Gbps**. `guest-load.sh` prints this conversion for you.

### 3.3 Manual equivalent

```bash
# copy the dirtier into the guest over the serial console
B=$(base64 -w0 dirtier.py)
sudo python3 con.py /tmp/conA.sock "echo $B | base64 -d > /tmp/dirtier.py"

# start it: 24 GiB working set, 1500 MiB/s
sudo python3 con.py /tmp/conA.sock \
  "setsid nohup python3 /tmp/dirtier.py 24 1500 > /tmp/d.log 2>&1 < /dev/null & echo ok"

# wait ~40 s for it to settle, then confirm
sudo python3 con.py /tmp/conA.sock "tail -1 /tmp/d.log"
# -> achieved 1500.0 MiB/s
```

Cross-check from the host, independent of the guest's own claim:

```bash
sudo python3 -c "
import sys,time; sys.path.insert(0,'.')
from migrate import QMP
q = QMP('/tmp/A.qmp')
q.cmd('calc-dirty-rate', **{'calc-time':10})
time.sleep(12)
print(q.cmd('query-dirty-rate'))
"
```


Notes:

* `dirtier.py` cycles **17 distinct 1 MiB patterns**. 17 is coprime with the
  chunk count, so the pattern landing on any given offset rotates each pass.
  This matters: `calc-dirty-rate` samples pages and compares *content hashes*,
  so a dirtier writing identical bytes reports **0 MB/s** even though the pages
  genuinely dirty the KVM log.
* **`stress-ng --vm-bytes` did not work here** (0.17.06): RSS plateaued around
  514 MB per worker regardless of settings, capping the dirty rate near
  0.4 GiB/s. Hence the purpose-built dirtier.
* Guest NIC naming differs between libvirt (`enp1s0`) and raw QEMU (`enp0s2`).
  If your image came from libvirt, its netplan will not match and the guest
  will have no network — use the serial console (`con.py`), not SSH.

---

## 4. Calculating throughput and time

### 4.1 Where the numbers come from

Everything is derived from `query-migrate` on the **source**:

```json
{
  "status": "completed",
  "total-time": 18668,
  "downtime": 304,
  "setup-time": 3,
  "ram": {
    "transferred": 48648421376,
    "remaining": 0,
    "mbps": 21382.9,
    "dirty-sync-count": 10,
    "dirty-pages-rate": 393216,
    "duplicate": 45123456
  }
}
```

| Field | Meaning |
|---|---|
| `total-time` | ms from `migrate` until completion. **This is the migration time.** |
| `downtime` | ms the guest was stopped on both hosts — the user-visible outage |
| `setup-time` | ms spent before data started flowing |
| `ram.transferred` | **bytes** actually pushed, including re-sends of re-dirtied pages |
| `ram.remaining` | bytes still outstanding; watch this to see convergence |
| `ram.mbps` | QEMU's instantaneous throughput in **megabits/s (10^6)** |
| `ram.dirty-sync-count` | number of dirty-bitmap sync rounds = iteration count |
| `ram.duplicate` | zero/duplicate pages elided, not transmitted |

### 4.2 Formulas

```
migration time (s)   = total-time / 1000          # or measured wall clock
downtime (ms)        = downtime

avg goodput (Mb/s)   = transferred_bytes * 8 / 1e6 / wall_seconds
avg goodput (MiB/s)  = transferred_bytes / 2**20 / wall_seconds
peak throughput      = max(ram.mbps) sampled during the run

transfer amplification = transferred_bytes / guest_RAM_bytes
```

`mbps` is **megabits per second, base 10** (QEMU computes
`bytes * 8 / 1e6 / seconds`). To get MiB/s: `mbps * 1e6 / 8 / 2**20`, i.e.
divide by roughly 8.39.

```
 5,274 mbps  ->   629 MiB/s      (TLS, single channel)
21,383 mbps  -> 2,549 MiB/s      (TLS, 8 channels)
```

`migrate.py` prints `throughput (peak)` and `avg goodput (wall)` for you and
records both in the JSON output.

### 4.3 Reading convergence

Watch `remaining` and `dirty-sync-count` in the progress output.

**Converging** — `remaining` falls monotonically toward the downtime threshold:
```
 25.1s active  sent=37.20 GiB  remaining=7.18 GiB   17310.1 mbps rounds=2
 35.1s active  sent=57.43 GiB  remaining=6.73 GiB   17310.1 mbps rounds=4
 45.1s active  sent=77.06 GiB  remaining=1.42 GiB   17065.2 mbps rounds=7
```

**Not converging** — sawtooth: `remaining` drops, then jumps back up each time
the dirty bitmap is re-synced, because the guest re-dirties faster than the
link drains:
```
230.6s active  sent=210.74 GiB  remaining=868.75 MiB  8328.5 mbps rounds=12
235.6s active  sent=215.48 GiB  remaining=10.44 GiB   8086.6 mbps rounds=13   <-- jumped back
245.6s active  sent=225.00 GiB  remaining=956.31 MiB  8080.3 mbps rounds=13
250.7s active  sent=229.63 GiB  remaining=18.92 GiB   7961.0 mbps rounds=14   <-- again
```
`transferred` climbing far past the guest's RAM size with `rounds` incrementing
steadily is the signature. The customer's 393 GiB guest shows the same shape.

**The convergence condition:**

```
migration throughput  >  guest dirty rate
```

Both in the same units. Everything else — multifd, auto-converge, post-copy —
is just a different way of satisfying it: multifd raises the left side,
auto-converge lowers the right side, post-copy abandons the requirement
entirely by cutting over first and faulting pages in afterwards.

### 4.4 Sizing multifd channels

Measured scaling on this host: **~4.2 Gbps per channel**, near-linear to 8
channels (128 cores, so no thread contention).

```
channels_needed  =  peak_dirty_rate_Gbps / 4.2      then double for headroom
```

Worked example — guest dirtying 1500 MiB/s = 12.6 Gbps:
`12.6 / 4.2 = 3` channels marginal, so use **6**. Measured: 4 channels
completed in 49 s, 6 in 25 s, 8 in 19 s; 2 channels never converged.

Per-channel throughput depends on your CPU's AES-NI/VAES performance — measure
it on your own hardware rather than reusing 4.2.

---

## 5. Measured results (QEMU 8.2.2, 192 GiB guest, 1500 MiB/s dirty rate)

Convergence bar: 1500 MiB/s = **12.6 Gbps**.

| Configuration | Result | Time | Downtime | Peak throughput |
|---|---|---|---|---|
| plaintext, idle guest | OK | 8.8 s | 325 ms | 26,093 mbps |
| TLS, idle guest | OK | 13.4 s | 246 ms | 5,274 mbps |
| plaintext, 1 channel | OK | 34.7 s | 316 ms | ~22,000 mbps |
| **TLS, 1 channel** | **FAIL** | aborted 300 s | — | 5,274 mbps |
| **TLS, 2 channels** | **FAIL** | aborted 300 s | — | 8,329 mbps |
| TLS, 4 channels | OK | 49.2 s | 350 ms | 17,480 mbps |
| TLS, 6 channels | OK | 24.7 s | 305 ms | 26,797 mbps |
| TLS, 8 channels | OK | 18.7 s | 304 ms | 33,599 mbps |
| TLS + auto-converge (defaults) | FAIL | aborted 420 s | — | throttle hit 70% |
| plaintext + post-copy | OK | 22.7 s | 33 ms | — |
| **TLS + post-copy (AES-GCM)** | **FAIL** `postcopy-paused` | paused at +10 s | — | 3,856 mbps |
| TLS + post-copy (ChaCha20) | OK | 242.7 s | 40 ms | 2,082 mbps |

### Two distinct defects

**(a) TLS caps a single migration stream at ~5.2 Gbps / ~650 MiB/s.** QEMU
encrypts in one migration thread. Independent of NIC speed. Any guest dirtying
faster than that can never converge. This is the customer's timeout.

**(b) TLS + post-copy breaks**, reproduced twice on loopback with
`Cannot read from TLS channel: Input/output error`. Root cause is a GnuTLS
TLS 1.3 AES-GCM auto-rekey thread-safety bug, triggered because post-copy's
return path shares one `gnutls_session_t` across two threads:

* <https://gitlab.com/qemu-project/qemu/-/issues/1937>
* <https://gitlab.com/gnutls/gnutls/-/issues/1717>

Fixed in **QEMU 10.1.0** (`QIO_CHANNEL_FEATURE_CONCURRENT_IO`) and
**GnuTLS 3.8.11**. Neither is in Ubuntu 24.04 (QEMU 8.2.2, GnuTLS 3.8.3).

To confirm the mechanism yourself, force a cipher with no auto-rekey:

```bash
TLSPRIO="NORMAL:-AES-256-GCM:-AES-128-GCM:-AES-128-CCM:-AES-256-CCM" \
  sudo -E ./launch-vm.sh B 2223 tls inc

sudo python3 -u ./migrate.py --src /tmp/A.qmp --dst /tmp/B.qmp --port 4444 \
     --tls --postcopy --timeout 600 \
     --tls-priority "NORMAL:-AES-256-GCM:-AES-128-GCM:-AES-128-CCM:-AES-256-CCM"
```

It completes — at roughly half the throughput, since ChaCha20 cannot use
AES-NI. That throughput cost is why ChaCha20 is a diagnostic, not a fix.

---

## 6. Cleanup

```bash
sudo ./cleanup.sh -n          # dry run: show what would happen, change nothing
sudo ./cleanup.sh             # graceful guest shutdown, then remove everything
sudo ./cleanup.sh -t 600      # allow longer for a busy guest to power off
sudo ./cleanup.sh -f          # skip graceful shutdown, SIGKILL (CORRUPTS THE DISK)
sudo ./cleanup.sh -k D        # remove everything EXCEPT vmD
```

`cleanup.sh` discovers VMs from the process table (matching `comm=qemu-system*`
with a `-name vm...` argument), so it finds them even when the pidfile was
deleted. It asks the guest to power off over the serial console, falls back to
an **ACPI power button via QMP** if the console is unusable, then waits
(default 240 s) for QEMU to exit on its own before removing stale
`.qmp` / `.sock` / `.pid` / `.log` files. If the guest will not power off it
**aborts rather than SIGKILL** — see below.

### 6.1 Never SIGKILL a running guest

Every test VM has the same qcow2 open with `file.locking=off`. SIGKILLing a
QEMU whose guest is still running leaves the guest's **ext4 root filesystem
dirty**. The damage is not obvious, and it presents as a baffling symptom:

> The VM launches. QEMU stays alive. RSS settles at ~3–4 GiB. The guest burns
> ~0 CPU. And the serial console returns **zero bytes** — `con.py` fails with
> `no shell prompt` no matter how many times you retry.

What is actually happening: the dirty root filesystem stops systemd bringing up
the `/boot` (`LABEL=BOOT`) and `/boot/efi` (`LABEL=UEFI`) device units, so the
boot ends in **emergency mode**. Ubuntu cloud images keep the root account
locked, so `sulogin` cannot open a maintenance shell and the console falls
permanently silent. The VM looks "booted but dead".

Observed first-hand: `Job dev-disk-by\x2dlabel-BOOT.device/start running
(1min / 1min 30s)` … `Emergency Mode`, with an offline `e2fsck` reporting
`Group 21 block bitmap does not match checksum` on the root partition —
while `/boot` and `/boot/efi` themselves were perfectly clean.

### 6.2 Recovering a guest with a dead console

A guest in this state cannot be rescued from inside — there is no console to
log in through. Stop every VM and fsck the image offline:

```bash
sudo ./cleanup.sh -f            # the guest is already unusable at this point
sudo ./repair-disk.sh           # read-only check (refuses while any VM runs)
sudo ./repair-disk.sh -y        # actually repair
sudo ./launch-vm.sh A 2222      # boots to a working console again
```

Confirm the repair:

```bash
sudo python3 con.py /tmp/conA.sock \
  "systemctl is-system-running; findmnt -n -o TARGET,SOURCE /boot /boot/efi"
```

```
degraded              <- 'degraded' is fine: only snapd fails (guest has no network)
/boot      /dev/vda16
/boot/efi  /dev/vda15
```

### Manual equivalent

```bash
# graceful guest shutdown (replace X with the VM in state 'running')
sudo python3 con.py /tmp/conX.sock "sudo pkill -f dirtier.py; sudo shutdown -h now" 60

# then reap everything by pidfile
for p in /tmp/*.pid; do sudo kill -9 "$(sudo cat $p)" 2>/dev/null; done
sudo rm -f /tmp/*.pid /tmp/*.qmp /tmp/con*.sock

# VMs whose pidfile was lost: get the pid from the process table
ps -eo pid,args | grep -- '-name vm' | grep -v grep
sudo kill -9 <pid>

ps -eo comm | grep qemu-system       # expect nothing
sudo virsh list --all                # testvm should be 'shut off'
```

Never use `pkill -f "name vmX"` — the pattern matches the invoking shell's own
command line.

