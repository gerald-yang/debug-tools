#!/bin/bash
# Sweep multifd channel counts under TLS.
#
#   sweep-channels.sh <SRC_NAME> <BASE_PORT> <N1> [N2 ...]
#
# The guest is chained: each destination becomes the next source. The sweep
# STOPS on the first failure and leaves the guest alive on the last good VM.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

SRC=$1; shift
PORT=$1; shift

i=0
for N in "$@"; do
  i=$((i+1))
  DST="S${N}"
  echo
  echo "######## multifd channels=$N   (vm$SRC -> vm$DST) ########"

  "$HERE/launch-vm.sh" "$DST" $((2300+N)) tls inc >/dev/null 2>&1
  sleep 2

  python3 -u "$HERE/migrate.py" \
      --src "/tmp/$SRC.qmp" --dst "/tmp/$DST.qmp" --port $((PORT+i)) \
      --tls --channels "$N" --timeout 300 --json /tmp/results.jsonl
  RC=$?

  echo "--- src stderr (/tmp/$SRC.log) ---"; tail -3 "/tmp/$SRC.log"
  echo "--- dst stderr (/tmp/$DST.log) ---"; tail -3 "/tmp/$DST.log"

  if [ "$RC" != "0" ]; then
    echo "!!!! channels=$N DID NOT COMPLETE (rc=$RC) - stopping sweep"
    echo "!!!! guest is still alive on vm$SRC"
    kill -9 "$(cat /tmp/$DST.pid 2>/dev/null)" 2>/dev/null
    rm -f "/tmp/$DST.pid"
    break
  fi

  # success: the guest now lives on $DST, so retire the old source
  kill -9 "$(cat /tmp/$SRC.pid 2>/dev/null)" 2>/dev/null
  rm -f "/tmp/$SRC.pid"
  SRC=$DST
  sleep 3
done

echo
echo "guest is now on vm$SRC  (qmp /tmp/$SRC.qmp, console /tmp/con$SRC.sock)"
echo "results appended to /tmp/results.jsonl"
