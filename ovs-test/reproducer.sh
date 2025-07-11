#!/bin/bash
#
# Test OVS CT udp traffic
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh
pktgen=$my_dir/scapy-traffic-tester.py

require_module act_ct

IP1="7.7.7.1"
IP2="7.7.7.2"
IP3="7.7.7.3"
IP4="7.7.7.4"
IP5="7.7.7.5"
IP6="7.7.7.6"
IP7="7.7.7.7"
IP8="7.7.7.8"

enable_switchdev
require_interfaces REP1 REP2 REP3 REP4 REP5 REP6 REP7 REP8
unbind_vfs
bind_vfs
reset_tc $REP1
reset_tc $REP2
reset_tc $REP3
reset_tc $REP4
reset_tc $REP5
reset_tc $REP6
reset_tc $REP7
reset_tc $REP8

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    ip netns del ns2 2> /dev/null
    ip netns del ns3 2> /dev/null
    ip netns del ns4 2> /dev/null
    ip netns del ns5 2> /dev/null
    ip netns del ns6 2> /dev/null
    ip netns del ns7 2> /dev/null
    reset_tc $REP1
    reset_tc $REP2
    reset_tc $REP3
    reset_tc $REP4
    reset_tc $REP5
    reset_tc $REP6
    reset_tc $REP7
    reset_tc $REP8
    ovs-vsctl del-br br-ovs
    pkill reproducer.sh
}
trap cleanup EXIT

function config_ovs() {
    local proto=$1

    echo "setup ovs"
    start_clean_openvswitch
    ovs-vsctl add-br br-ovs
    ovs-vsctl add-port br-ovs $REP1
    ovs-vsctl add-port br-ovs $REP2
    ovs-vsctl add-port br-ovs $REP3
    ovs-vsctl add-port br-ovs $REP4
    ovs-vsctl add-port br-ovs $REP5
    ovs-vsctl add-port br-ovs $REP6
    ovs-vsctl add-port br-ovs $REP7
    ovs-vsctl add-port br-ovs $REP8

    ovs-ofctl add-flow br-ovs in_port=$REP1,dl_type=0x0806,actions=output:$REP2
    ovs-ofctl add-flow br-ovs in_port=$REP2,dl_type=0x0806,actions=output:$REP1
    ovs-ofctl add-flow br-ovs in_port=$REP3,dl_type=0x0806,actions=output:$REP4
    ovs-ofctl add-flow br-ovs in_port=$REP4,dl_type=0x0806,actions=output:$REP3
    ovs-ofctl add-flow br-ovs in_port=$REP5,dl_type=0x0806,actions=output:$REP6
    ovs-ofctl add-flow br-ovs in_port=$REP6,dl_type=0x0806,actions=output:$REP5
    ovs-ofctl add-flow br-ovs in_port=$REP7,dl_type=0x0806,actions=output:$REP8
    ovs-ofctl add-flow br-ovs in_port=$REP8,dl_type=0x0806,actions=output:$REP7

    ovs-ofctl add-flow br-ovs "table=0, $proto,ct_state=-trk actions=ct(table=1)"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+new actions=ct(commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, $proto,ct_state=+trk+est actions=normal"

    ovs-ofctl dump-flows br-ovs --color
}

function run_stress() {
    local ns=$1
    local vf=$2
    local src_ip=$3
    local dst_ip=$4
    local port_base=$5
    local port_count=$6
    local t=$7

    while true; do
        ip netns exec $ns $pktgen -i $vf --src-ip $src_ip --dst-ip $dst_ip --time $t --src-port $port_base --src-port-count $port_count --dst-port $port_count --dst-port-count 1 --pkt-count 1 --inter 0
        sleep 2
    done
}

function run() {
    title "Test OVS CT UDP"
    config_vf ns0 $VF1 $REP1 $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    config_vf ns2 $VF3 $REP3 $IP3
    config_vf ns3 $VF4 $REP4 $IP4
    config_vf ns4 $VF5 $REP5 $IP5
    config_vf ns5 $VF6 $REP6 $IP6
    config_vf ns6 $VF7 $REP7 $IP7
    config_vf ns7 $VF8 $REP8 $IP8

    proto="udp"
    config_ovs $proto

    t=10
    port_base=1000
    port_count=499
    echo "sniff packets on $REP"
    timeout $t tcpdump -qnnei $REP -c 2 $proto &
    pid1=$!

    echo "run traffic for $t seconds $VF2"
    ip netns exec ns1 $pktgen -l -i $VF2 --src-ip $IP1 --time $((t+1)) &
    ip netns exec ns3 $pktgen -l -i $VF4 --src-ip $IP3 --time $((t+1)) &
    ip netns exec ns5 $pktgen -l -i $VF6 --src-ip $IP5 --time $((t+1)) &
    ip netns exec ns7 $pktgen -l -i $VF8 --src-ip $IP7 --time $((t+1)) &
    sleep 5

    for i in $(seq 0 63); do
        run_thread ns0 $VF1 $IP1 $IP2 $port_base $port_count $t &
        port_base=$((port_base + 50))
        sleep 0.6
    done
    sleep 1
    for i in $(seq 0 63); do
        run_thread ns2 $VF3 $IP3 $IP4 $port_base $port_count $t &
        port_base=$((port_base + 50))
        sleep 0.6
    done
    sleep 1
    for i in $(seq 0 63); do
        run_thread ns4 $VF5 $IP5 $IP6 $port_base $port_count $t &
        port_base=$((port_base + 50))
        sleep 0.7
    done
    sleep 1
    for i in $(seq 0 63); do
        run_thread ns6 $VF7 $IP7 $IP8 $port_base $port_count $t &
        port_base=$((port_base + 50))
        sleep 0.7
    done
}

run

# wait here until user press any key to stop
read -n 1
