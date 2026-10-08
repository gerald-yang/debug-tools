#!/usr/bin/env python3
"""
Show every test VM on this host and what state it is in.

  sudo ./vm-status.py [NAME ...]

With no arguments it discovers VMs from /tmp/*.qmp and /tmp/*.pid.

State column meanings:
  running      guest is executing here  -> usable as a migration SOURCE
  inmigrate    armed with -incoming, no guest yet -> usable as a DESTINATION
  postmigrate  guest already migrated AWAY -> spent, kill it
  paused       stopped (often mid-cutover or a failed incoming)
  DEAD         pidfile/socket present but the process is gone
  BUSY         QMP socket is held by another client (a migration is running)
"""
import glob, json, os, re, socket, sys, time

USE = {
    'running':     'SOURCE   (guest runs here)',
    'inmigrate':   'DEST     (armed, awaiting incoming)',
    'postmigrate': 'SPENT    (guest migrated away - kill it)',
    'paused':      'PAUSED   (check logs)',
    'finish-migrate': 'SPENT (cutover done)',
}


def qmp(path, timeout=3.0):
    """Return (status, migrate_status, error_desc) or raise."""
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(timeout)
    s.connect(path)
    f = s.makefile('rw', encoding='utf-8', newline='\n')

    def recv():
        while True:
            line = f.readline()
            if not line:
                raise EOFError
            o = json.loads(line)
            if 'event' not in o:
                return o

    def cmd(name):
        f.write(json.dumps({'execute': name}) + '\n')
        f.flush()
        r = recv()
        if 'error' in r:
            raise RuntimeError(r['error'])
        return r.get('return')

    recv()                      # greeting
    cmd('qmp_capabilities')
    st = cmd('query-status')['status']
    mig = cmd('query-migrate')
    s.close()
    return st, mig.get('status'), mig.get('error-desc')


def pid_of(name):
    p = '/tmp/%s.pid' % name
    if not os.path.exists(p):
        return None
    try:
        with open(p) as fh:
            return int(fh.read().strip())
    except (ValueError, OSError):
        return None


def alive(pid):
    return pid is not None and os.path.exists('/proc/%d' % pid)


def cmdline(pid):
    try:
        with open('/proc/%d/cmdline' % pid, 'rb') as fh:
            return fh.read().replace(b'\0', b' ').decode('utf-8', 'replace')
    except OSError:
        return ''


def discover():
    names = set()
    for pat, strip in (('/tmp/*.qmp', '.qmp'), ('/tmp/*.pid', '.pid')):
        for f in glob.glob(pat):
            names.add(os.path.basename(f)[:-len(strip)])
    # only keep ones that look like a launch-vm.sh instance
    return sorted(n for n in names
                  if os.path.exists('/tmp/%s.qmp' % n) or os.path.exists('/tmp/%s.pid' % n))


def main():
    names = sys.argv[1:] or discover()
    if not names:
        print("no test VMs found (no /tmp/*.qmp or /tmp/*.pid)")
        return

    hdr = "%-6s %-8s %-15s %-14s %-34s %s" % (
        "VM", "PID", "STATE", "MIGRATE", "ROLE", "FLAGS")
    print(hdr)
    print("-" * len(hdr))

    for n in names:
        pid = pid_of(n)
        sock = '/tmp/%s.qmp' % n
        cl = cmdline(pid) if alive(pid) else ''

        flags = []
        if '-incoming' in cl:
            flags.append('incoming')
        if 'tls-creds-x509' in cl:
            flags.append('tls')
        m = re.search(r'priority=([^ ,]+)', cl)
        if m:
            flags.append('prio=' + m.group(1)[:18])
        m = re.search(r'hostfwd=tcp:127\.0\.0\.1:(\d+)', cl)
        if m:
            flags.append('ssh=' + m.group(1))

        if not alive(pid) and not os.path.exists(sock):
            continue
        if not alive(pid):
            print("%-6s %-8s %-15s %-14s %-34s %s" % (
                n, pid or '-', 'DEAD', '-', 'stale files - rm /tmp/%s.*' % n,
                ' '.join(flags)))
            continue

        try:
            st, mig, err = qmp(sock)
        except (socket.timeout, BlockingIOError):
            print("%-6s %-8d %-15s %-14s %-34s %s" % (
                n, pid, 'BUSY', '-', 'QMP held by another client', ' '.join(flags)))
            continue
        except Exception as e:
            print("%-6s %-8d %-15s %-14s %-34s %s" % (
                n, pid, 'NO-QMP', '-', str(e)[:34], ' '.join(flags)))
            continue

        role = USE.get(st, '?')
        if st == 'running' and mig == 'completed':
            role = 'SOURCE   (received a guest)'
        if mig in ('postcopy-paused', 'postcopy-active'):
            role = 'POST-COPY - do NOT migrate_cancel'
        print("%-6s %-8d %-15s %-14s %-34s %s" % (
            n, pid, st, mig or '-', role, ' '.join(flags)))
        if err:
            print("%-6s %-8s error-desc: %s" % ('', '', err))

    print()
    print("ready to use as SOURCE      : state 'running'")
    print("ready to use as DESTINATION : state 'inmigrate'")
    print("stderr for any VM           : sudo cat /tmp/<NAME>.log")


if __name__ == '__main__':
    main()
