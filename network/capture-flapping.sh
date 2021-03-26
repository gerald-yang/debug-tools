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

port_p=${ports//,/ or port }
port_p="port $port_p"
echo "ports: $port_p"

timeout="$restart_timeout"
current_date=$(date --rfc-3339=seconds | awk '{print $1}')
current_time=$(date --rfc-3339=seconds | awk '{print $2}' | cut -f1 -d'+')
echo "begin capture at: ${current_date}T${current_time}"
echo ""

curr_time=$(date '+%Y.%m.%d-%H.%M.%S')
data_dir="data-$curr_time"
mkdir -p "$data_dir"
bonddir="/proc/net/bonding/"

function collect_sys_info()
{
	sys_dir=$(date '+%Y.%m.%d-%H.%M.%S')
	mkdir -p "$data_dir/$sys_dir"

	cat /proc/softirqs > "$data_dir/$sys_dir/proc-softirqs"
	cat /proc/interrupts > "$data_dir/$sys_dir/proc-interrupts"
	cat /proc/vmstat > "$data_dir/$sys_dir/proc-vmstat"
	cat /proc/zoneinfo > "$data_dir/$sys_dir/proc-zoneinfo"
	cat /proc/meminfo > "$data_dir/$sys_dir/proc-meminfo"
	cat /proc/pagetypeinfo > "$data_dir/$sys_dir/proc-pagetypeinfo"
	cat /proc/slabinfo > "$data_dir/$sys_dir/proc-slabinfo"
	nstat > "$data_dir/$sys_dir/nstat"
	netstat -s > "$data_dir/$sys_dir/netstat_-s"
	ethtool -S enp6s0f0 > "$data_dir/$sys_dir/ethtool_-S_enp6s0f0"
	ethtool -S enp6s0f1 > "$data_dir/$sys_dir/ethtool_-S_enp6s0f1"
	#ethtool -S enp1s0 > "$data_dir/$sys_dir/ethtool_-S_enp1s0"
	ip -s -s -d link show > "$data_dir/$sys_dir/ip_-s_-s_-d_link_show"
	ip -o addr > "$data_dir/$sys_dir/ip_-o_addr"
	cat /proc/net/snmp > "$data_dir/$sys_dir/proc-net-snmp"
	cat /proc/net/netstat > "$data_dir/$sys_dir/proc-net-netstat"
	cat /proc/net/softnet_stat > "$data_dir/$sys_dir/proc-net-softnet_stat"
	cat /proc/net/sockstat > "$data_dir/$sys_dir/proc-net-sockstat"
	tc -s qdisc show dev enp6s0f0 > "$data_dir/$sys_dir/tc_-s_qdisc_show_dev_enp6s0f0"
	tc -s qdisc show dev enp6s0f1 > "$data_dir/$sys_dir/tc_-s_qdisc_show_dev_enp6s0f1"
	#tc -s qdisc show dev enp1s0 > "$data_dir/$sys_dir/tc_-s_qdisc_show_dev_enp1s0"
	if [ -d $bonddir ]; then
		mkdir -p "$data_dir/$sys_dir/bond"
		for bond in $(ls $bonddir); do
			cat $bonddir/$bond > "$data_dir/$sys_dir/bond/$bond"
		done
	fi
}

function keep_monitor()
{
	timeout=$((timeout - 1))
	collect_sys_info

	if ((timeout > 0)) ; then
		echo "keep monitoring ... "
		echo "restart tcpdump after $timeout minutes"
	else
		echo "timeout"
		echo "restart tcpdump and clear logs"
		timeout="$restart_timeout"
		kill "$tcpdump_pid"
		rm -rf "$output_file"
		tcpdump -nlei any $port_p -w "$data_dir/$output_file" &
		tcpdump_pid=$!
	fi
}

collect_sys_info
tcpdump -nlei any $port_p -w "$data_dir/$output_file" &
tcpdump_pid=$!

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

