CDATE=$(date +%F.%H.%M)

if [ "$(id -u)" != "0" ]; then
	echo "Need root permission" 1>&2
	exit 1
fi

if [ ! -d "./flamegraph" ]; then
	git clone https://github.com/brendangregg/flamegraph
fi

sar -A > "$CDATE".sar
ps auxS > "$CDATE".ps
perf record -ag sleep 30
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
