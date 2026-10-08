#!/bin/bash
# Run several migrations back-to-back, handling all the per-run bookkeeping.
#
#   run-matrix.sh <SRC_NAME> <BASE_PORT> "<opts1>" "<opts2>" ...
#
# Each "<opts>" is a set of migrate.py options, e.g.
#
#   ./run-matrix.sh A 4500 \
#       ""                                    \
#       "--tls"                               \
#       "--tls --channels 4"                  \
#       "--tls --channels 8"                  \
#       "--tls --postcopy"
#
# For every run this script will:
#   1. launch a FRESH destination VM (TLS-enabled iff the opts contain --tls)
#   2. allocate a NEW migration port
#   3. run migrate.py
#   4. on success  : the guest now lives on the destination, so that VM
#                    becomes the source for the next run and the old source
#                    is killed by pidfile
#      on failure  : stop, leaving the guest alive on the current source
#
# Results are appended to /tmp/results.jsonl.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

SRC=$1; shift
BASEPORT=$1; shift

RESULTS=${RESULTS:-/tmp/results.jsonl}
TIMEOUT=${TIMEOUT:-300}
SSHPORT=2400
run=0

for OPTS in "$@"; do
  run=$((run + 1))
  DST="D${run}"
  SSHPORT=$((SSHPORT + 1))
  PORT=$((BASEPORT + run))

  # destination must carry TLS creds iff this run uses TLS
  DTLS=""
  case "$OPTS" in *--tls*) DTLS="tls" ;; esac

  # propagate a custom GnuTLS priority string to the destination object
  PRIO=""
  case "$OPTS" in
    *--tls-priority*) PRIO=$(echo "$OPTS" | sed -n 's/.*--tls-priority[ =]\+\([^ ]*\).*/\1/p') ;;
  esac

  echo
  echo "================================================================"
  echo "run $run:  vm$SRC -> vm$DST   port=$PORT"
  echo "opts   :  ${OPTS:-<plaintext, single channel>}"
  echo "================================================================"

  TLSPRIO="$PRIO" "$HERE/launch-vm.sh" "$DST" "$SSHPORT" "$DTLS" inc >/dev/null 2>&1
  sleep 2

  # shellcheck disable=SC2086
  python3 -u "$HERE/migrate.py" \
      --src "/tmp/$SRC.qmp" --dst "/tmp/$DST.qmp" --port "$PORT" \
      --timeout "$TIMEOUT" --json "$RESULTS" $OPTS
  RC=$?

  echo "--- src stderr (/tmp/$SRC.log) ---"; tail -3 "/tmp/$SRC.log" 2>/dev/null
  echo "--- dst stderr (/tmp/$DST.log) ---"; tail -3 "/tmp/$DST.log" 2>/dev/null

  if [ "$RC" != "0" ]; then
    echo
    echo "!!!! run $run DID NOT COMPLETE (rc=$RC)"
    echo "!!!! stopping. The guest is still alive and running on vm$SRC."
    echo "!!!! Re-run the remaining cases with vm$SRC as the source."
    kill -9 "$(cat /tmp/$DST.pid 2>/dev/null)" 2>/dev/null
    rm -f "/tmp/$DST.pid"
    break
  fi

  # success -> guest is on $DST; retire the spent source
  kill -9 "$(cat /tmp/$SRC.pid 2>/dev/null)" 2>/dev/null
  rm -f "/tmp/$SRC.pid"
  SRC=$DST
  sleep 3
done

echo
echo "guest is now on vm$SRC  (qmp /tmp/$SRC.qmp, console /tmp/con$SRC.sock)"
echo
python3 "$HERE/summarise.py" "$RESULTS"
