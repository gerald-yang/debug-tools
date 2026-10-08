#!/bin/bash
# Manage the in-guest memory dirtier over the serial console.
#
#   guest-load.sh <VM> start <WORKING_SET_GiB> <RATE_MiB_s>
#   guest-load.sh <VM> status      # host-side truth + guest detail if reachable
#   guest-load.sh <VM> verify      # independent QMP calc-dirty-rate measurement
#   guest-load.sh <VM> stop
#
# <VM> is the launch-vm.sh name, e.g. A  (console /tmp/conA.sock)
#
# The dirtier runs INSIDE the guest and therefore MIGRATES WITH IT -- start it
# once on your first source VM and it keeps running across every migration in
# the matrix. Use the destination's name after each hop.
#
# 'start' is GATED on host-side proof that the guest really faulted in the
# working set. If the console command silently fails, this script fails too --
# it will never let you run a migration against an idle guest and believe you
# measured a dirty one.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

VM=${1:?usage: guest-load.sh <VM> start|status|verify|stop [GiB] [MiB/s]}
ACTION=${2:?usage: guest-load.sh <VM> start|status|verify|stop [GiB] [MiB/s]}
CON="/tmp/con${VM}.sock"
PIDFILE="/tmp/${VM}.pid"

[ -S "$CON" ] || { echo "FATAL: no console socket $CON (is vm$VM running? ./vm-status.py)" >&2; exit 1; }

pid() { cat "$PIDFILE" 2>/dev/null; }
# RSS of the QEMU process == guest pages actually faulted in. This is the
# authoritative, console-independent signal that the dirtier allocated memory.
rss_gib() { ps -o rss= -p "$(pid)" 2>/dev/null | awk '{printf "%.2f", $1/1048576}'; }
# Guest CPU burn: a dirtier pegs ~1 core (100 ticks/s). An idle guest is ~0.
cpu_ticks() {
  local p a b; p=$(pid)
  a=$(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null || echo 0)
  sleep "${1:-3}"
  b=$(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null || echo 0)
  echo $((b - a))
}

# Every console command is checked. con.py exits non-zero if the console is
# unusable; previously that failure was discarded and the caller marched on.
gcmd() {
  local out
  if ! out=$(python3 "$HERE/con.py" "$CON" "$1" "${2:-180}" 2>&1); then
    echo "$out" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

case "$ACTION" in

  start)
    GIB=${3:?need working-set size in GiB, e.g. 24}
    RATE=${4:?need dirty rate in MiB/s, e.g. 1500}
    [ -s "$PIDFILE" ] || { echo "FATAL: no $PIDFILE - cannot verify from the host." >&2; exit 1; }

    echo "vm$VM pid $(pid), RSS before: $(rss_gib) GiB"

    # ONE console session for upload+launch: each con.py disconnect HUPs the
    # guest's getty, and several in a row can trip systemd's restart limit.
    B=$(base64 -w0 "$HERE/dirtier.py")
    echo "uploading dirtier.py and starting ${GIB} GiB @ ${RATE} MiB/s..."
    if ! out=$(gcmd "echo $B | base64 -d > /tmp/dirtier.py && \
pkill -f '[d]irtier.py'; sleep 1; \
setsid nohup python3 /tmp/dirtier.py $GIB $RATE > /tmp/d.log 2>&1 < /dev/null & \
sleep 3; pgrep -f '[d]irtier.py' > /dev/null && echo DIRTIER_UP || { echo DIRTIER_DOWN; cat /tmp/d.log; }" 120); then
      echo "FATAL: could not drive the guest console - dirtier NOT started." >&2
      exit 1
    fi
    printf '%s\n' "$out"
    case "$out" in
      *DIRTIER_UP*) ;;
      *) echo "FATAL: dirtier failed to start inside the guest (see output above)." >&2; exit 1 ;;
    esac

    # Host-side gate: wait for the guest to actually fault in the working set.
    want=$(awk -v g="$GIB" 'BEGIN{printf "%.2f", g*0.85}')
    echo "waiting for guest RSS to reach ${want} GiB (prefaulting ${GIB} GiB)..."
    ok=0
    for _ in $(seq 1 60); do
      now=$(rss_gib)
      printf '\r  RSS now: %s GiB   ' "$now"
      if awk -v a="$now" -v b="$want" 'BEGIN{exit !(a>=b)}'; then ok=1; break; fi
      sleep 5
    done
    echo
    if [ "$ok" != 1 ]; then
      echo "FATAL: guest RSS never reached ${want} GiB (stuck at $(rss_gib) GiB)." >&2
      echo "  The dirtier is not dirtying. DO NOT run a migration now - it would" >&2
      echo "  measure an idle guest and look deceptively fast." >&2
      exit 1
    fi

    echo "guest CPU burn: $(cpu_ticks 3) ticks/3s  (dirtier should be >100; idle is ~0)"
    gcmd "tail -2 /tmp/d.log" 60 || true
    echo
    echo "OK: ${RATE} MiB/s = $(python3 -c "print('%.1f' % ($RATE*8*1048576/1e9))") Gbps."
    echo "    Migration throughput must EXCEED this to converge."
    ;;

  status)
    # Host-side facts first: these work even when the serial console is wedged.
    echo "=== host-side (authoritative) ==="
    if [ -s "$PIDFILE" ] && kill -0 "$(pid)" 2>/dev/null; then
      echo "  vm$VM pid      : $(pid)"
      echo "  guest RSS      : $(rss_gib) GiB   <- must be >= working set"
      echo "  CPU ticks/3s   : $(cpu_ticks 3)   <- >100 = dirtying, ~0 = IDLE"
    else
      echo "  vm$VM is not running (no live $PIDFILE)"; exit 1
    fi
    echo "=== in-guest (needs a working serial console) ==="
    gcmd "pgrep -af '[d]irtier.py' || echo 'NOT RUNNING'; tail -2 /tmp/d.log 2>/dev/null; free -g | sed -n 2p" 90 \
      || echo "  (console unreachable - trust the host-side numbers above)"
    ;;

  verify)
    echo "host-side measurement via QMP calc-dirty-rate (10s sample)..."
    HERE="$HERE" python3 - "$VM" <<'PY'
import sys, os, time
sys.path.insert(0, os.environ['HERE'])
from migrate import QMP
vm = sys.argv[1]
q = QMP('/tmp/%s.qmp' % vm)
q.cmd('calc-dirty-rate', **{'calc-time': 10})
time.sleep(12)
r = q.cmd('query-dirty-rate')
mb = r.get('dirty-rate')
print("  status     :", r.get('status'))
print("  dirty-rate : %s MB/s" % mb)
if mb:
    print("  that is    : %.1f MiB/s = %.1f Gbps" % (mb*1e6/2**20, mb*8/1000.0))
PY
    ;;

  stop)
    gcmd "pkill -f '[d]irtier.py'; sleep 1; pgrep -af '[d]irtier.py' || echo 'stopped'" 90 \
      || { echo "console unreachable; the dirtier dies with the guest anyway." >&2; exit 1; }
    ;;

  *)
    echo "unknown action '$ACTION' (start|status|verify|stop)" >&2
    exit 1
    ;;
esac
