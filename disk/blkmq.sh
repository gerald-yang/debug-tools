#!/bin/bash

DEV="$1"
if [ -z "$DEV" ]; then
	echo "No parameter"
	exit 1
fi

queued_ary=[]
count="0"

for q in /sys/block/nvme0n1/mq/*; do
	queued=$(cat "$q"/queued)
	queued_ary["$count"]="$queued"
	count=$((count+1))
done

fio -filename="$DEV" -direct=1 -iodepth 128 -thread -rw=randwrite -randrepeat=0 -ioengine=libaio -bs=4k -numjobs=1 -runtime=30 -group_reporting -name=nvmetest -time_based

count="0"
for q in /sys/block/nvme0n1/mq/*; do
	queued=$(cat "$q"/queued)
	queued_ary["$count"]=$(($queued - queued_ary[$count]))
	count=$((count+1))
done

QD="queued.diff"
echo "Record" > "$QD"
count="0"
for q in /sys/block/nvme0n1/mq/*; do
	cpu_list=$(cat "$q"/cpu_list)
	echo "queued ${queued_ary["$count"]} , cpu_list: $cpu_list"  >> "$QD"
        count=$((count+1))
done

total="0"
for t in ${queued_ary[@]}; do
	total=$((total+t))
done

echo "total requests: $total" >> "$QD"
