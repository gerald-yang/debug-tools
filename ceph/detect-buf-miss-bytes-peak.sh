#!/bin/bash

if [ "$EUID" != 0 ]; then
	echo "Please run this script as root"
	exit 1
fi

function help_usage()
{
	echo "Usage:"
	echo "sudo ./detect-buf-miss-bytes-peak.sh -i OSD_ID -s START_HOUR -e END_HOUR -t DIFF_THRESHOLD"
	echo ""
	echo "OSD_ID: OSD ID"
	echo "START_HOUR, END_HOUR: only detect peaks in this time window START_HOUR to END_HOUR"
        echo "DIFF_THRESHOLD: threshold for bluestore_buffer_miss_bytes diff between every minute"
	echo ""
	echo "example:"
	echo "sudo ./detect-buf-miss-bytes-peak.sh -i 2 -s 00 -e 07 -t 800000000"
	echo "detect if bluestore_buffer_miss_bytes diff between every minute is higher then 800000000 on osd.2, then collect logs"
	echo ""
}


while getopts i:s:e:t:h  flag
do
	case "$flag" in
		i)
			osd_id="$OPTARG"
			;;
		s)
			start_hour="$OPTARG"
			;;
		e)
                        end_hour="$OPTARG"
			;;
		t)
			threshold="$OPTARG"
			;;
		h)
			help_usage
			exit 0
			;;
                *)
                        help_usage
                        exit 0
                        ;;
	esac
done

if [ -z "$osd_id" ] || [ -z "$start_hour" ] || [ -z "$end_hour" ] || [ -z "$threshold" ]; then
	echo "please specify all arguments"
	echo ""
	help_usage
	exit 1
fi

if [[ $start_hour -gt 23 ]] || [[ $start_hour -lt 0 ]]; then
        echo "valid start_hour: 00 - 23"
        exit 1
fi

if [[ $end_hour -gt 23 ]] || [[ $end_hour -lt 0 ]]; then
        echo "valid end_hour: 00 - 23"
        exit 1
fi

#period=1
period=60
count=2
prev=""

function get_diff {
	curr=$(ceph daemon osd."$osd_id" perf dump bluestore | jq .bluestore.bluestore_buffer_miss_bytes)
	if [ -n "$prev" ]; then
		dvalue=$((curr - prev))
	else
		dvalue=0
	fi
	prev="$curr"
	echo "$dvalue"
}

function wait_peak_end {
	prev=$(ceph daemon osd."$osd_id" perf dump bluestore | jq .bluestore.bluestore_buffer_miss_bytes)
	while true; do
		sleep "$period"
		get_diff
		if ((dvalue < threshold)) ;then
			break
		fi
	done
}

function collect_logs {
	ceph tell osd."$osd_id" injectargs '--debug_osd=20 --debug_optracker=20 --debug_bluestore=15 --debug_ms=20'
	sleep 60
	ceph tell osd."$osd_id" injectargs '--debug_osd=1/5 --debug_optracker=0/5 --debug_bluestore=1/5 --debug_ms=0/5'
}

function check_peak {
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
}

echo "Monitoring OSD $osd_id, bluestore_buffer_miss_bytes diff threshold $threshold"
echo "Time window: $start_hour - $end_hour"
echo ""

while true; do
        curr_hour=$(date +%H)
        #echo "current: $curr_hour"
        if [[ $start_hour -gt $end_hour ]]; then
                if [[ $curr_hour -ge $start_hour ]]; then
                        check_peak
                elif [[ $curr_hour -lt $end_hour ]]; then
                        check_peak
                fi
        else
                if [[ $curr_hour -ge $start_hour ]] && [[ $curr_hour -lt $end_hour ]]; then
                        check_peak
                fi
        fi

	sleep "$period"
done
