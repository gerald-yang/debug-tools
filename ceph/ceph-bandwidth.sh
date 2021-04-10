#!/bin/bash

if [ -z "$1" ]; then
        echo "enter ceph.log"
        exit 1
fi

grep 'PiB avail' "$1" | while read -r line; do
	ts=$(echo "$line" | awk '{print $1}')
        rd=$(echo "$line" | awk -F 's rd' '{print $1}' | awk '{print $(NF-1), $NF, "s"}')
        wd=$(echo "$line" | awk -F 's wr' '{print $1}' | awk '{print $(NF-1), $NF, "s"}')
        echo "$ts   $rd   $wd"
done 
