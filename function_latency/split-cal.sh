#!/bin/bash

if ! [ -f "trace.dat" ]; then
        echo "Can not find trace.dat"
        exit 1
fi

trace-cmd report | grep ' us ' > temp
total_line=$(wc -l temp | awk '{print $1}')
echo "total line: $total_line"

rm -f tempsplit*
part=$(echo "($total_line / 20) + 1" | bc)
split -l $part temp tempsplit

percent="0"
avg_latency="0"
iter="0"

for pf in tempsplit*; do
	echo "processing $pf"
	./cal.sh "$pf" &
	pids[$iter]=$!
	echo "add pid: ${pids[$iter]}"
	(( iter = iter + 1 ))
done

echo "waiting for calculation"
for pid in ${pids[*]};
do
	wait "$pid"
done
echo "done"

sleep 2
./average.sh > average_latency
