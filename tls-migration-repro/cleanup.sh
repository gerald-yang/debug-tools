#!/bin/bash
# Stop and remove every test VM created by launch-vm.sh.
#
#   cleanup.sh [-n] [-f] [-k NAME]... [-t SECONDS]
#
#   -n          dry run: show what would be done, change nothing
#   -f          force: skip the graceful shutdown and kill immediately.
#               THIS CORRUPTS THE SHARED qcow2 if a guest is still running.
#   -k NAME     keep this VM (repeatable)
#   -t SECONDS  how long to wait for a clean power-off (default 240)
#
# By default the VM that is actually running the guest is shut down cleanly
# first, then everything is killed and stale sockets/pidfiles/logs removed.
#
# WHY THIS MATTERS: every test VM has the same qcow2 open with file.locking=off.
# SIGKILLing a QEMU whose guest is still running leaves the guest's ext4 root
# filesystem dirty. The next boot then fails its device/mount units and drops
# into emergency mode -- and because Ubuntu cloud images have the root account
# locked, the serial console goes permanently silent and the VM looks "booted
# but dead". Recovering needs an offline e2fsck (see README section 6).
# So: this script will NOT SIGKILL a guest that is still running unless you
# pass -f.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

DRY=0
FORCE=0
KEEP=" "
WAIT=240
while getopts "nfk:t:" o; do
  case "$o" in
    n) DRY=1 ;;
    f) FORCE=1 ;;
    k) KEEP="$KEEP$OPTARG " ;;
    t) WAIT="$OPTARG" ;;
    *) echo "usage: $0 [-n] [-f] [-k NAME]... [-t SECONDS]" >&2; exit 1 ;;
  esac
done

run() {
  if [ "$DRY" = "1" ]; then
    echo "   DRY: $*"
  else
    eval "$@"
  fi
}

# ---- discover every running QEMU started by launch-vm.sh --------------------
# Match on comm=qemu-system* so this never self-matches the shell running it.
mapfile -t VMS < <(ps -eo pid= -o comm= -o args= |
  awk '$2 ~ /^qemu-system/ {
         for (i = 3; i <= NF; i++)
           if ($i == "-name" && $(i+1) ~ /^vm/) { print $1, substr($(i+1), 3) }
       }')

if [ "${#VMS[@]}" -eq 0 ]; then
  echo "no running test VMs found."
else
  echo "found ${#VMS[@]} test VM(s):"
  printf '   pid=%s  name=vm%s\n' $(printf '%s\n' "${VMS[@]}")
  echo
fi

# ---- graceful shutdown of whichever VM currently holds the guest ------------
DIRTY=""
if [ "$FORCE" = "0" ] && [ "${#VMS[@]}" -gt 0 ]; then
  for entry in "${VMS[@]}"; do
    set -- $entry
    PID=$1; NAME=$2
    case "$KEEP" in *" $NAME "*) continue ;; esac
    [ -S "/tmp/$NAME.qmp" ] || continue

    STATE=$(python3 - "$NAME" <<'PY' 2>/dev/null
import sys, os
sys.path.insert(0, os.environ.get('KITDIR', '.'))
try:
    from migrate import QMP
    print(QMP('/tmp/%s.qmp' % sys.argv[1], connect_timeout=3).cmd('query-status')['status'])
except Exception:
    print('unknown')
PY
)
    if [ "$STATE" = "running" ]; then
      echo "vm$NAME is running the guest -> graceful shutdown"
      # 1) ask the guest politely over the serial console
      if [ -S "/tmp/con$NAME.sock" ]; then
        run "python3 '$HERE/con.py' /tmp/con$NAME.sock 'sudo pkill -f \"[d]irtier.py\"; sudo systemctl poweroff -i' 60 >/dev/null 2>&1" \
          || echo "   console shutdown failed (console may be wedged) - falling back to ACPI"
      else
        echo "   no console socket - using ACPI"
      fi
      # 2) ACPI power button: works even when the console is unusable
      run "python3 - <<'PY' >/dev/null 2>&1 || true
import sys, os
sys.path.insert(0, '$HERE')
from migrate import QMP
QMP('/tmp/$NAME.qmp', connect_timeout=3).cmd('system_powerdown')
PY" || true

      if [ "$DRY" = "0" ]; then
        echo "   waiting up to ${WAIT}s for QEMU to exit on its own..."
        gone=0
        for _ in $(seq "$WAIT"); do
          kill -0 "$PID" 2>/dev/null || { gone=1; break; }
          sleep 1
        done
        if [ "$gone" = "1" ]; then
          echo "   vm$NAME powered off cleanly"
        else
          echo "   WARNING: vm$NAME did not power off within ${WAIT}s" >&2
          DIRTY="$DIRTY$NAME "
        fi
      fi
    fi
  done
fi

# ---- refuse to corrupt the disk --------------------------------------------
if [ -n "$DIRTY" ] && [ "$FORCE" = "0" ]; then
  echo >&2
  echo "ABORTING: vm${DIRTY% } still has a LIVE guest that would not power off." >&2
  echo "  SIGKILLing it now would leave the shared qcow2 root filesystem dirty," >&2
  echo "  and the guest would next boot into emergency mode with a dead console." >&2
  echo >&2
  echo "  Options:" >&2
  echo "    - give it longer:        sudo ./cleanup.sh -t 600" >&2
  echo "    - check what it is doing: sudo ./guest-load.sh <VM> status" >&2
  echo "    - accept the damage:     sudo ./cleanup.sh -f   (then repair, see README section 6)" >&2
  exit 1
fi

# ---- kill whatever is left --------------------------------------------------
for entry in "${VMS[@]:-}"; do
  [ -n "${entry:-}" ] || continue
  set -- $entry
  PID=$1; NAME=$2
  case "$KEEP" in
    *" $NAME "*) echo "keeping vm$NAME (pid $PID)"; continue ;;
  esac
  if kill -0 "$PID" 2>/dev/null; then
    echo "killing vm$NAME (pid $PID)"
    run "kill -9 $PID 2>/dev/null || true"
  else
    echo "vm$NAME (pid $PID) already gone"
  fi
done

# ---- remove stale files, but not for VMs we are keeping ---------------------
if [ "$DRY" = "0" ]; then sleep 2; fi
echo
echo "removing stale sockets / pidfiles / logs..."
for f in /tmp/*.qmp /tmp/con*.sock /tmp/*.pid /tmp/*.log; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  n=${base%.*}
  n=${n#con}
  case "$KEEP" in *" $n "*) echo "   keeping $f"; continue ;; esac
  # don't touch unrelated files that happen to live in /tmp
  case "$base" in
    *.qmp|*.pid) ;;
    con*.sock)   ;;
    *.log) [ -e "/tmp/$n.qmp" ] || [ -e "/tmp/$n.pid" ] || \
           printf '%s' "$KEEP" >/dev/null ;;
  esac
  run "rm -f '$f'"
done

echo
REMAIN=$(ps -eo comm= | grep -c '^qemu-system' || true)
echo "qemu processes remaining: $REMAIN"
[ "$DRY" = "1" ] && echo "(dry run - nothing was actually changed)"
echo
echo "libvirt domains on this host:"
virsh list --all 2>/dev/null || echo "   (virsh unavailable)"
