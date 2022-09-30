#!/bin/bash

OSD_ID="$1"

if [ -z "$OSD_ID" ]; then
	echo "please enter OSD ID"
	exit 1
fi

#period=1
period=60
#threshold=160000000
threshold=800000000
count=2
prev=""

function get_diff {
	curr=$(sudo ceph daemon osd."$OSD_ID" perf dump bluestore | jq .bluestore.bluestore_buffer_miss_bytes)
	if ! [ -z "$prev" ]; then
		dvalue=$((curr - prev))
	else
		dvalue=0
	fi
	prev="$curr"
	echo "$dvalue"
}

function wait_peak_end {
	while true; do
		sleep "$period"
		get_diff
		if ((dvalue < threshold)) ;then
			break
		fi
	done
}

function collect_logs {
	sudo ceph tell osd."$OSD_ID" injectargs '--debug_osd=20 --debug_optracker=20 --debug_bluestore=15 --debug_ms=20'
	sleep 60
	sudo ceph tell osd."$OSD_ID" injectargs '--debug_osd=1/5 --debug_optracker=0/5 --debug_bluestore=1/5 --debug_ms=0/5'
}

while true; do
	get_diff
	if ((dvalue > threshold)) ;then
		if ((count < 2)); then
			((count += 1))
		else
			echo "find peak, collect logs and wait until peak ends"
			collect_logs
			wait_peak_end
			prev=""
			count=0
		fi
	else
		count=0
	fi

	sleep "$period"
done
