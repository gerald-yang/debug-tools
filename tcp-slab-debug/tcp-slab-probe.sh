#!/bin/bash


if ! [ $(id -u) -eq 0 ]; then
        echo "please run this script as root"
        exit 1
fi

if dpkg -l | grep -q trace-cmd; then
        echo "trace-cmd found"
else
        echo "trace-cmd not found"
        apt install trace-cmd -y
fi

while true; do
        trace-cmd record -b 30000 -e kmem:kmem_cache_alloc -f 'bytes_req == 2000' -T sleep 20
        curr_time=$(date '+%Y.%m.%d-%H.%M.%S')
        trace-cmd report > "$curr_time".report
        ./stackcollapse-tracecmd.pl "$curr_time".report > trace.fold
        ./flamegraph.pl trace.fold > "$curr_time".svg
        rm -f trace.dat trace.fold
        sleep 300
done
