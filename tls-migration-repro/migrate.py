#!/usr/bin/env python3
"""
Single-host QEMU live-migration test driver.

Usage:
  migrate.py --src SRC.qmp --dst DST.qmp --port N [options]

Options:
  --tls                  enable QEMU-native TLS on the migration stream
  --channels N           multifd channel count (N>1 implies multifd capability)
  --postcopy             enable post-copy, switch after 2 dirty-sync rounds
  --autoconverge         enable auto-converge CPU throttling
  --throttle-initial N   auto-converge starting throttle %  (QEMU default 20)
  --throttle-increment N auto-converge step %               (QEMU default 10)
  --tls-priority STR     GnuTLS priority string for the creds object
  --downtime-limit MS    max permitted stop time, ms (QEMU default 300)
  --max-bandwidth BPS    0 = unlimited (QEMU default is 128 MiB/s -- always override)
  --timeout S            give up after S seconds
  --json FILE            append a one-line JSON result record

Exit code 0 only if the migration reaches 'completed'.
"""
import argparse, json, socket, sys, time


def _qemu_rss_gib(qmp_path):
    """Resident size of the QEMU process owning qmp_path == guest pages faulted in.
    Finds the pid by matching the QMP socket path in each process's cmdline."""
    import os, glob
    try:
        for d in glob.glob('/proc/[0-9]*'):
            try:
                with open(d + '/cmdline', 'rb') as f:
                    cl = f.read().decode('utf-8', 'replace')
            except OSError:
                continue
            if qmp_path not in cl or 'qemu-system' not in cl:
                continue
            with open(d + '/status') as f:
                for line in f:
                    if line.startswith('VmRSS:'):
                        return int(line.split()[1]) / 1048576.0
    except Exception:
        pass
    return None


class QMP:
    """Minimal synchronous QMP client over a UNIX socket."""

    def __init__(self, path, connect_timeout=120):
        deadline = time.time() + connect_timeout
        while True:
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(path)
                break
            except OSError:
                if time.time() > deadline:
                    raise RuntimeError("cannot connect to QMP socket %s" % path)
                time.sleep(0.1)
        self.f = self.s.makefile('rw', encoding='utf-8', newline='\n')
        self._recv()               # greeting
        self.cmd('qmp_capabilities')

    def _recv(self):
        while True:
            line = self.f.readline()
            if not line:
                raise EOFError("QMP connection closed")
            obj = json.loads(line)
            if 'event' in obj:     # ignore async events
                continue
            return obj

    def cmd(self, name, **args):
        req = {'execute': name}
        if args:
            req['arguments'] = args
        self.f.write(json.dumps(req) + '\n')
        self.f.flush()
        r = self._recv()
        if 'error' in r:
            raise RuntimeError(r['error'])
        return r.get('return')


def human(n):
    n = float(n or 0)
    for u in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if n < 1024:
            return "%.2f %s" % (n, u)
        n /= 1024.0
    return "%.2f PiB" % n


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--src', required=True)
    p.add_argument('--dst', required=True)
    p.add_argument('--port', required=True, type=int)
    p.add_argument('--host', default='127.0.0.1')
    p.add_argument('--tls', action='store_true')
    p.add_argument('--tls-dir', default='/tmp/pki')
    p.add_argument('--tls-hostname', default='localhost')
    p.add_argument('--tls-priority', default='')
    p.add_argument('--channels', type=int, default=1)
    p.add_argument('--postcopy', action='store_true')
    p.add_argument('--autoconverge', action='store_true')
    p.add_argument('--throttle-initial', type=int)
    p.add_argument('--throttle-increment', type=int)
    p.add_argument('--downtime-limit', type=int, default=300)
    p.add_argument('--max-bandwidth', type=int, default=0)
    p.add_argument('--timeout', type=int, default=300)
    p.add_argument('--expect-rss-gib', type=float, default=0,
                   help='abort unless the source guest has ~this many GiB resident '
                        '(catches "my dirtier never started" before you waste a run)')
    p.add_argument('--interval', type=float, default=5.0)
    p.add_argument('--json')
    a = p.parse_args()

    uri = 'tcp:%s:%d' % (a.host, a.port)
    multifd = a.channels > 1
    # Every capability must be stated explicitly (True AND False): capabilities
    # persist on a QEMU instance across successive migrations.
    caps = [
        {'capability': 'multifd',       'state': multifd},
        {'capability': 'postcopy-ram',  'state': a.postcopy},
        {'capability': 'auto-converge', 'state': a.autoconverge},
    ]
    # client-side creds id must differ per priority string: an object id cannot
    # be redefined once added, and a QEMU that was previously a destination
    # already owns the server-side id 'tls0'.
    cli_id = 'tlscli' + ('p' if a.tls_priority else '')

    label = "%s + %s%s" % (
        "TLS" if a.tls else "PLAINTEXT",
        ("multifd x%d" % a.channels) if multifd else "single-channel",
        (", postcopy" if a.postcopy else "") + (", autoconverge" if a.autoconverge else ""))

    # ---------------- destination ----------------
    dst = QMP(a.dst)
    # A destination is single-use. A fresh '-incoming defer' QEMU sits in
    # 'inmigrate'; anything else means this instance has already been used
    # (or was not started with -incoming defer at all).
    dst_state = dst.cmd('query-status')['status']
    if dst_state != 'inmigrate':
        sys.exit(
            "FATAL: destination %s is in state '%s', expected 'inmigrate'.\n"
            "  A destination VM can only accept ONE migration. Kill it and\n"
            "  launch a fresh one:\n"
            "      sudo kill -9 $(sudo cat /tmp/<NAME>.pid)\n"
            "      sudo ./launch-vm.sh <NAME> <sshport> %s inc\n"
            "  (and make sure it was launched with the 'inc' argument)"
            % (a.dst, dst_state, 'tls' if a.tls else '\"\"'))

    dst.cmd('migrate-set-parameters',
            **({'tls-creds': 'tls0', 'tls-hostname': a.tls_hostname}
               if a.tls else {'tls-creds': ''}))
    dst.cmd('migrate-set-capabilities', capabilities=caps)
    if multifd:
        # MUST be set before migrate-incoming, else:
        # "Multifd must be set before incoming starts"
        dst.cmd('migrate-set-parameters', **{'multifd-channels': a.channels})
    dst.cmd('migrate-incoming', uri=uri)
    print("destination armed: %s on %s" % (label, uri))

    # ---------------- source ----------------
    src = QMP(a.src)
    src_state = src.cmd('query-status')['status']
    if src_state != 'running':
        hint = ""
        if src_state == 'postmigrate':
            hint = ("\n  'postmigrate' means this VM ALREADY migrated away -- the guest\n"
                    "  now lives on the previous destination. Use that VM as your source.")
        elif src_state == 'inmigrate':
            hint = ("\n  'inmigrate' means this VM was started with -incoming and has not\n"
                    "  received a guest yet. It is a destination, not a source.")
        sys.exit("FATAL: source %s is in state '%s', expected 'running'.%s"
                 % (a.src, src_state, hint))

    # Warn loudly if the guest looks idle. The single most common way to get a
    # meaningless result is to migrate a guest whose dirtier never started: the
    # run completes in seconds and looks like a pass, but it measured nothing.
    if a.expect_rss_gib:
        rss_gib = _qemu_rss_gib(a.src)
        if rss_gib is not None and rss_gib < a.expect_rss_gib * 0.85:
            sys.exit("FATAL: source guest has only %.2f GiB resident, expected "
                     "~%.0f GiB.\n  The in-guest load is NOT running -- this migration would "
                     "measure an idle\n  guest and finish deceptively fast. Start it with:\n"
                     "      sudo ./guest-load.sh <VM> start <GiB> <MiB/s>"
                     % (rss_gib, a.expect_rss_gib))
        print("source guest resident: %.2f GiB" % rss_gib)

    params = {'max-bandwidth': a.max_bandwidth, 'downtime-limit': a.downtime_limit}
    if a.tls:
        obj = {'qom-type': 'tls-creds-x509', 'id': cli_id,
               'dir': a.tls_dir, 'endpoint': 'client', 'verify-peer': True}
        if a.tls_priority:
            obj['priority'] = a.tls_priority
        try:
            src.cmd('object-add', **obj)
        except RuntimeError as e:
            print("object-add (already present?):", e)
        params['tls-creds'] = cli_id
        params['tls-hostname'] = a.tls_hostname
    else:
        params['tls-creds'] = ''          # must clear, it persists
    if multifd:
        params['multifd-channels'] = a.channels
    if a.throttle_initial is not None:
        params['cpu-throttle-initial'] = a.throttle_initial
    if a.throttle_increment is not None:
        params['cpu-throttle-increment'] = a.throttle_increment
    src.cmd('migrate-set-parameters', **params)
    src.cmd('migrate-set-capabilities', capabilities=caps)

    print("\n=== %s | giving up after %ds ===" % (label, a.timeout))
    hdr = "  %8s %-16s %-11s %-11s %10s %7s %6s"
    print(hdr % ("elapsed", "status", "sent", "remaining", "mbps", "rounds", "thr%"))

    t0 = time.time()
    src.cmd('migrate', uri=uri)

    last = 0.0
    pc_at = paused_at = None
    aborted = False
    r = {}
    peak_mbps = 0.0
    TERMINAL = ('completed', 'failed', 'cancelled')

    while True:
        r = src.cmd('query-migrate')
        st = r.get('status')
        now = time.time()
        el = now - t0
        if st in TERMINAL:
            break
        ram = r.get('ram', {})
        peak_mbps = max(peak_mbps, ram.get('mbps') or 0.0)

        if st == 'postcopy-paused' and paused_at is None:
            paused_at = el
            print("  !! POSTCOPY-PAUSED at %.1fs  error-desc=%r" % (el, r.get('error-desc')))

        if a.postcopy and pc_at is None and (ram.get('dirty-sync-count') or 0) >= 2:
            print("  -> switching to post-copy at %.1fs" % el)
            src.cmd('migrate-start-postcopy')
            pc_at = el

        if el > a.timeout:
            aborted = True
            if str(st).startswith('postcopy'):
                # migrate_cancel during post-copy crashes QEMU
                # (runstate_set assertion) and destroys the guest.
                print("  !! timeout, status=%s -> NOT cancelling (unsafe in post-copy)" % st)
                break
            print("  !! timeout -> migrate_cancel")
            src.cmd('migrate_cancel')
            time.sleep(3)
            r = src.cmd('query-migrate')
            st = r.get('status')
            break

        if el - last >= a.interval:
            last = el
            print(hdr % ("%.1fs" % el, st, human(ram.get('transferred')),
                         human(ram.get('remaining')), "%.1f" % (ram.get('mbps') or 0),
                         ram.get('dirty-sync-count'), r.get('cpu-throttle-percentage')))
        time.sleep(0.2)

    wall = time.time() - t0
    ram = r.get('ram', {})
    peak_mbps = max(peak_mbps, ram.get('mbps') or 0.0)
    ok = (st == 'completed')

    print("\n=== RESULT: %s%s ===" % (st, "" if ok else "  <<< NOT COMPLETED"))
    rows = [
        ("configuration",        label),
        ("wall clock",           "%.2f s" % wall),
        ("qemu total-time",      "%s ms" % r.get('total-time')),
        ("downtime",             "%s ms" % r.get('downtime')),
        ("setup time",           "%s ms" % r.get('setup-time')),
        ("ram transferred",      human(ram.get('transferred'))),
        ("ram remaining",        human(ram.get('remaining'))),
        ("throughput (final)",   "%.1f mbps" % (ram.get('mbps') or 0)),
        ("throughput (peak)",    "%.1f mbps" % peak_mbps),
        ("avg goodput (wall)",   "%.1f mbps" % (
            (ram.get('transferred') or 0) * 8 / 1e6 / wall if wall else 0)),
        ("dirty sync rounds",    ram.get('dirty-sync-count')),
        ("dirty pages rate",     "%s pages/s" % ram.get('dirty-pages-rate')),
        ("cpu throttle",         "%s %%" % r.get('cpu-throttle-percentage')),
        ("postcopy started at",  "%.1f s" % pc_at if pc_at else None),
        ("postcopy paused at",   "%.1f s" % paused_at if paused_at else None),
        ("error-desc",           r.get('error-desc')),
    ]
    for k, v in rows:
        print("  %-20s: %s" % (k, v))

    if a.json:
        rec = {'status': st, 'completed': ok, 'tls': a.tls, 'channels': a.channels,
               'postcopy': a.postcopy, 'autoconverge': a.autoconverge,
               'tls_priority': a.tls_priority, 'wall_s': round(wall, 2),
               'total_time_ms': r.get('total-time'), 'downtime_ms': r.get('downtime'),
               'transferred_bytes': ram.get('transferred'), 'final_mbps': ram.get('mbps'),
               'peak_mbps': round(peak_mbps, 1), 'rounds': ram.get('dirty-sync-count'),
               'throttle_pct': r.get('cpu-throttle-percentage'),
               'postcopy_started_s': pc_at, 'postcopy_paused_s': paused_at,
               'error_desc': r.get('error-desc'), 'aborted': aborted}
        with open(a.json, 'a') as fh:
            fh.write(json.dumps(rec) + '\n')
        print("\n  appended JSON record to %s" % a.json)

    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
