#!/bin/bash

sf="$1"

if [ -z "$pf" ]; then
        echo "please enter file name"
        exit 1
fi

result="$1".result
echo "result" > "$result"

fline=$(wc -l $sf | awk '{print $1}')
LAT=$(awk -F 'us' '{print $1}' $sf | awk '{print $NF}')
part_latency="0"
total_count="0"

echo "$sf lines: $fline" >> "$result"
while read -r line
do
	p=$(echo "$total_count % 10000" | bc)
	if [ "$p" = "0" ]; then
		echo "$total_count" >> "$result"
	fi
	total_count=$((total_count + 1))
	part_latency=$(echo "$part_latency + $line" | bc)
done < <(printf '%s' "$LAT")

part_latency=$(echo "scale=3; $part_latency / $total_count" | bc)
echo "average: $part_latency" >> "$result"

