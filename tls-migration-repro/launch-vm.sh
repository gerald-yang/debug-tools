#!/bin/bash
# Launch one QEMU instance for single-host migration testing.
#
#   launch-vm.sh <NAME> <SSH_FWD_PORT> [tls] [incoming]
#
#   tls       - attach a tls-creds-x509 object (id=tls0, server endpoint)
#   incoming  - start with "-incoming defer" (i.e. act as a migration DESTINATION)
#
# Set TLSPRIO to pass a GnuTLS priority string, e.g.
#   TLSPRIO="NORMAL:-AES-256-GCM:-AES-128-GCM:-AES-128-CCM:-AES-256-CCM"
set -u

NAME=$1
SSHPORT=$2
TLS=${3:-}
INC=${4:-}

DISK=${DISK:-/home/ubuntu/testvm.img}
MEM=${MEM:-192G}
CPUS=${CPUS:-48}
PKI=${PKI:-/tmp/pki}

ARGS=""
if [ "$TLS" = "tls" ]; then
  ARGS="-object tls-creds-x509,id=tls0,dir=$PKI,endpoint=server,verify-peer=on${TLSPRIO:+,priority=$TLSPRIO}"
fi
if [ "$INC" = "inc" ]; then
  ARGS="$ARGS -incoming defer"
fi

# ---- preflight: never clobber a VM that is already running -----------------
if [ -f "/tmp/$NAME.pid" ] && kill -0 "$(cat /tmp/$NAME.pid 2>/dev/null)" 2>/dev/null; then
  echo "REFUSING: vm$NAME is already running (pid $(cat /tmp/$NAME.pid))." >&2
  echo "  Pick a different name, or stop it first:" >&2
  echo "      sudo kill -9 \$(sudo cat /tmp/$NAME.pid)" >&2
  exit 1
fi
if ps -eo comm= -o args= | awk -v n="-name vm$NAME " \
     '$1 ~ /^qemu-system/ && index($0, n) > 0 { found = 1 } END { exit !found }'; then
  echo "REFUSING: a QEMU process is already named vm$NAME (pidfile may have been removed)." >&2
  echo "  Find it with:  ps -eo pid,args | grep -- '-name vm$NAME '" >&2
  exit 1
fi
if ss -ltn 2>/dev/null | grep -q "127.0.0.1:$SSHPORT "; then
  echo "REFUSING: 127.0.0.1:$SSHPORT is already in use - pick another SSH forward port." >&2
  ss -ltnp 2>/dev/null | grep "127.0.0.1:$SSHPORT " >&2
  exit 1
fi

rm -f "/tmp/$NAME.qmp" "/tmp/con$NAME.sock" "/tmp/$NAME.pid"
# NOTE: file.locking=off is required so source and destination can both hold
# the same qcow2 open. Safe here only because exactly one of them runs the
# guest at any instant. NEVER do this with two genuinely live guests.
setsid qemu-system-x86_64 \
  -name "vm$NAME" \
  -machine q35,accel=kvm -cpu host \
  -m "$MEM" -smp "$CPUS" \
  -drive file="$DISK",if=virtio,format=qcow2,file.locking=off \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$SSHPORT-:22 \
  -device virtio-net-pci,netdev=n0 \
  -display none \
  -qmp unix:/tmp/$NAME.qmp,server=on,wait=off \
  -serial unix:/tmp/con$NAME.sock,server=on,wait=off \
  -pidfile /tmp/$NAME.pid \
  $ARGS \
  > "/tmp/$NAME.log" 2>&1 < /dev/null &

sleep 3

# ---- postflight: QEMU exits silently on bad args; catch it -----------------
if [ ! -s "/tmp/$NAME.pid" ] || ! kill -0 "$(cat /tmp/$NAME.pid 2>/dev/null)" 2>/dev/null; then
  echo "FAILED to launch vm$NAME - QEMU exited. Its stderr was:" >&2
  echo "---------------------------------------------------------" >&2
  cat "/tmp/$NAME.log" >&2
  echo "---------------------------------------------------------" >&2
  rm -f "/tmp/$NAME.pid"
  exit 1
fi

echo "launched vm$NAME"
echo "  pid     : $(cat /tmp/$NAME.pid 2>/dev/null)"
echo "  qmp     : /tmp/$NAME.qmp"
echo "  console : /tmp/con$NAME.sock"
echo "  stderr  : /tmp/$NAME.log     <-- always check this after a failure"
