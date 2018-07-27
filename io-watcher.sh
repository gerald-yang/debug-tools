#!/bin/bash

# this script is used to check if any disk util is greater than 80
# collect some system data by iotop, iostat, blktrace

while true;
do
	date
	echo "start checking"
	DISK=$(iostat -d -x | grep sd[a-z] | awk '{print $1}')
	UTIL=$(iostat -d -x | grep sd[a-z] | awk '{print $14}')

	ADISK=($DISK)
	AUTIL=($UTIL)

	totaldisk=${#ADISK[@]}
	needsleep=false
	for (( i=0; i<$totaldisk; i++))
	do
		d=${ADISK[i]}
		u=${AUTIL[i]:0:-3}
		if [ "$u" -ge "80" ]; then
			needsleep=true
			LOGDIR=$(date +"%m-%d-%T")
			mkdir "$LOGDIR"
			echo "$d util is $u, starting record to $LOGDIR"
			iotop -b -o -n 10 > "$LOGDIR"/iotop-process.log
			iotop -b -n 10 > "$LOGDIR"/iotop-thread.log
			iostat -d -x 1 10 > "$LOGDIR"/iostat.log
			blktrace -w 60 -D "$LOGDIR" -d /dev/"$d" 
		fi
	done
	if [ "$needsleep" = true ]; then
		echo "record done, sleep 240 seconds"
		sleep 240
	fi
	sleep 60
done

