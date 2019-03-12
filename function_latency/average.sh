#!/bin/bash

avg_latency="0"
count="0"
called="0"

for sf in tempsplit*.result; do
	#echo "adding $sf"
	p=$(tail -n 1 "$sf" | awk '{print $2}')
	c=$(grep 'tempsplit' $sf | awk '{print $3}')
	called=$(echo "$called + $c" | bc)
	count=$((count+1))
	avg_latency=$(echo "$avg_latency + $p" | bc)
done

echo "$count"
echo "called: $called"
avg_latency=$(echo "scale=3; $avg_latency / $count" | bc)
echo "average latency: $avg_latency"
total_time=$(echo "scale=3; $avg_latency * $called / 1000000" | bc)
echo "total time: $total_time"
