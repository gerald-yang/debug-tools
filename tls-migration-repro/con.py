import socket, time, sys, re

class Con:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX); self.s.connect(path)
        self.s.settimeout(0.4); self.buf = ''
    def pump(self, t=1.0):
        end = time.time()+t
        while time.time() < end:
            try:
                d = self.s.recv(65536)
                if d: self.buf += d.decode('utf-8','replace')
            except socket.timeout: pass
            except BlockingIOError: pass
        return self.buf
    def expect(self, pats, timeout=90):
        if isinstance(pats,str): pats=[pats]
        end = time.time()+timeout
        while time.time() < end:
            try:
                d = self.s.recv(65536)
                if d: self.buf += d.decode('utf-8','replace')
            except socket.timeout: pass
            except BlockingIOError: pass
            for p in pats:
                if p in self.buf: return p
        return None
    def send(self, s):
        self.s.sendall((s+'\n').encode())

PROMPT = 'RDY>'

def ensure_shell(c):
    c.buf=''; c.send(''); c.pump(2)
    tail = c.buf[-400:]
    if 'login:' in tail:
        c.buf=''; c.send('ubuntu')
        if not c.expect(['assword'], 20): raise RuntimeError('no password prompt')
        c.buf=''; c.send('1234')
        if not c.expect(['$','~'], 30): raise RuntimeError('login failed')
    c.buf=''; c.send("export PS1='%s '" % PROMPT); c.pump(2)
    c.buf=''; c.send('')
    if not c.expect([PROMPT], 15): raise RuntimeError('no shell prompt')
    return True

def run(c, cmd, timeout=180):
    n = int(time.time()*1000 % 1000000)
    m = 'MK%dEND' % n
    a, b = m[:3], m[3:]
    c.buf=''
    c.send('%s; echo "%s""%s"' % (cmd, a, b))
    if not c.expect([m], timeout):
        return '<<TIMEOUT>>\n'+c.buf
    out = c.buf
    out = out.split('\n',1)[1] if '\n' in out else out
    idx = out.rfind(m)
    out = out[:idx]

    return out.replace('\r','').strip()

if __name__ == '__main__':
    av = sys.argv[1:]
    sock = '/tmp/con.sock'
    if av and av[0].startswith('/'):
        sock = av.pop(0)
    cmd = av[0]
    to = int(av[1]) if len(av) > 1 else 180

    # The serial console is flaky right after boot/migration, and every
    # disconnect HUPs the guest's getty. Retry, but back off so we do not
    # trip systemd's restart limit on serial-getty@ttyS0.
    last = 'unknown'
    for attempt in range(3):
        c = None
        try:
            c = Con(sock)
            ensure_shell(c)
            out = run(c, cmd, to)
            if out.startswith('<<TIMEOUT>>'):
                last = 'command timed out after %ss' % to
            else:
                print(out)
                sys.exit(0)
        except Exception as e:
            last = '%s: %s' % (type(e).__name__, e)
        finally:
            if c is not None:
                try: c.s.close()
                except Exception: pass
        time.sleep(5)

    sys.stderr.write(
        "con.py: serial console on %s is unusable after 3 attempts (%s).\n"
        "  The guest may be fine but its serial getty may have hit systemd's\n"
        "  restart limit (5 starts / 10s) from repeated console connections.\n"
        "  Check from the host instead:  ./guest-load.sh <VM> status\n" % (sock, last))
    sys.exit(1)
