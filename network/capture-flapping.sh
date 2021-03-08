#!/bin/bash

if [ "$EUID" != 0 ]; then
	echo "Please run this script as root"
	exit 1
fi

function help_usage()
{
	echo "Usage:"
	echo "sudo ./capture_flapping.sh -l OSD_LOG -o OSD_PEER -r RESTART_TIMEOUT -f OUTPUT_FILE -p PORT"
	echo ""
	echo "OSD_LOG: OSD log file to monitor flapping message"
	echo "OSD_PEER: OSD peer"
	echo "RESTART_TIMEOUT: if we don't see the flapping message after TIMEOUT minutes, restart tcpdump and delete logs"
	echo "OUTPUT_FILE: output file name"
	echo "PORT: port number to watch, separated by ','"
	echo ""
	echo "example 1:"
	echo "sudo ./capture_flapping.sh -l /var/log/ceph/ceph-osd.76.log -o osd.46 -r 30 -f osd76.pcap -p 6824,6825,6826,6827,6830,6831"
	echo "Every 30 minutes, if we do not see 'no reply from xxx osd.46' in /var/log/ceph/ceph-osd.76.log"
	echo "stop tcpdump, delete logs and restart tcpdump"
	echo "Write logs to osd76.pcap"
	echo "Capture packets on port 6824,6825,6826,6827,6830,6831"
	echo ""
	echo "example 2:"
	echo "sudo ./capture_flapping.sh -l /var/log/ceph/ceph-osd.46.log -o osd.76 -r 30 -f osd46.pcap -p 6801,6803,6807,6819,6820,6823,6821,6829"
	echo ""
}

while getopts l:o:r:f:p:h flag
do
	case "$flag" in
		l)
			osd_log="$OPTARG"
			;;
		o)
			osd_peer="$OPTARG"
			;;
		r)
			restart_timeout="$OPTARG"
			;;
		f)
			output_file="$OPTARG"
			;;
		p)
			ports="$OPTARG"
			;;
		h)
			help_usage
			exit 0
			;;
                *)
                        help_usage
                        exit0
                        ;;
	esac
done

if [ -z "$osd_log" ] || [ -z "$osd_peer" ] || [ -z "$restart_timeout" ] || [ -z "$output_file" ] || [ -z "$ports" ]; then
	echo "please specify all arguments"
	echo ""
	help_usage
	exit 1
fi

echo "restart tcpdump and clear logs every $restart_timeout if we don't see flapping message for peer $osd_peer"
echo "output file: $output_file"
echo "ports: $ports"

port_p=${ports//,/ or port }
port_p="port $port_p"

timeout="$restart_timeout"
current_date=$(date --rfc-3339=seconds | awk '{print $1}')
current_time=$(date --rfc-3339=seconds | awk '{print $2}' | cut -f1 -d'+')
echo "begin capture: ${current_date}T${current_time}"

tcpdump -nlei any $port_p -w "$output_file" &
tcpdump_pid=$!

function keep_monitor()
{
	timeout=$((timeout - 1))
	if ((timeout > 0)) ; then
		echo "keep monitoring ... "
		echo "restart tcpdump after $timeout minutes"
	else
		echo "timeout"
		echo "restart tcpdump and clear logs"
		timeout="$restart_timeout"
		kill "$tcpdump_pid"
		rm -rf "$output_file"
		tcpdump -nlei any $port_p -w "$output_file" &
		tcpdump_pid=$!
	fi
}

while true
do
	sleep 60
	flapping=$(grep 'no reply from' "$osd_log" | grep "$osd_peer" | tail -n 1)
	if [ -z "$flapping" ]; then
		keep_monitor
	else
		flapping_date=$(echo "$flapping" | awk '{print $1}')
		flapping_time=$(echo "$flapping" | awk '{print $2}')
		if [[ "${flapping_date}T${flapping_time}" > "${current_date}T${current_time}" ]]; then
			echo "catch flapping at: ${flapping_date}T${flapping_time}"
			kill "$tcpdump_pid"
			exit 0
		else
			keep_monitor
		fi
	fi
done

