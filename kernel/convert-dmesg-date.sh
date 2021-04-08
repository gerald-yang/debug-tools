#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
	echo "enter [dmesg] [uptime] [date] files"
	exit 1
fi

# how many seconds the system is up
ud=$(awk '{print $3}' "$2")
ud=$((ud * 24 * 60 * 60))
ut=$(awk '{print $5}' "$2" | cut -d',' -f1)
ut=$(date -d "1970-01-01 $ut" +%s)
ut=$((ut + ud))

# how many seconds from 1970-1-1 00:00:00 to now
ts=$(date +%s -f "$3")


while read -r line; do
        # kts kernel timestamp in seconds
	kts=$(echo "$line" | cut -d']' -f1)
	kmsg=$(echo "$line" | cut -d']' -f2-)
	kts=${kts:1}
	kts=$(echo "$kts" | awk '{$1=$1;print}') 

        # convert seconds to date
	real_kts=$(date -d "1970-1-1 + $ts sec - $ut sec + $kts sec" +"%F %T")
	echo "$real_kts $kmsg"
done < "$1"

