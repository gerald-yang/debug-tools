#!/bin/sh

CDATE=$(date +%F.%H.%M)

if [ "$(id -u)" != "0" ]; then
	echo "Need root permission" 1>&2
	exit 1
fi

if [ ! -d "./flamegraph" ]; then
	git clone https://github.com/brendangregg/flamegraph
fi

if ! rpm -q sysstat 2>&1 > /dev/null; then
	yum install -y sysstat
fi

if [ -z "$1" ]; then
	sar -A > "$CDATE".sar
	ps auxS > "$CDATE".ps
	perf record -ag sleep 300

	if [ -f "./perf.data" ]; then
		perf script > perf.data.script
		./flamegraph/stackcollapse-perf.pl perf.data.script > out.fold
		./flamegraph/flamegraph.pl out.fold > "$CDATE".svg
		mv perf.data perf.data."$CDATE"
		rm -f perf.data.script out.fold
	else
		echo "Failed to generate perf.data"
		exit 1
	fi
else
	if [ -f "$1" ]; then
		perf script "$1" > "$1".script
		./flamegraph/stackcollapse-perf.pl "$1".script > "$1".fold
		./flamegraph/flamegraph.pl "$1".fold > "$1".svg
		rm -f "$1".script "$1".fold
	else
		echo "Failed to open $1"
		exit 1
	fi
fi
