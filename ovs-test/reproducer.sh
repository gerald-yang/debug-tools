#!/bin/bash

my_dir="$(dirname "$0")"
. $my_dir/common.sh

require_module act_ct
echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal

IP1="7.7.7.1"
IP2="7.7.7.2"
IP3="7.7.7.3"
IP4="7.7.7.4"
IP5="7.7.7.5"
IP6="7.7.7.6"
IP7="7.7.7.7"
IP8="7.7.7.8"

config_sriov 8
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
    conntrack -F &>/dev/null
    ip netns del ns0 2> /dev/null
    ip netns del ns1 2> /dev/null
    ip netns del ns2 2> /dev/null
    ip netns del ns3 2> /dev/null
    ip netns del ns4 2> /dev/null
    ip netns del ns5 2> /dev/null
    ip netns del ns6 2> /dev/null
    ip netns del ns7 2> /dev/null
    ip netns del ns8 2> /dev/null
    reset_tc $REP1
    reset_tc $REP2
    reset_tc $REP3
    reset_tc $REP4
    reset_tc $REP5
    reset_tc $REP6
    reset_tc $REP7
    reset_tc $REP8
}
trap cleanup EXIT

function clean_processes() {
    pkill -9 reproducer.sh&>/dev/null
    pkill -9 iperf &>/dev/null
}
trap clean_processes EXIT

function add_del_table() {
    while true; do
        ovs-ofctl del-flows br-ovs "table=1, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.1 actions=ct(table=5,zone=80)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.2 actions=ct(table=5,zone=80)" &

        ovs-ofctl del-flows br-ovs "table=2, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.3 actions=ct(table=6,zone=79)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.4 actions=ct(table=6,zone=79)" &

        ovs-ofctl del-flows br-ovs "table=3, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.5 actions=ct(table=7,zone=78)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.6 actions=ct(table=7,zone=78)" &

        ovs-ofctl del-flows br-ovs "table=4, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.7 actions=ct(table=8,zone=76)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.8 actions=ct(table=8,zone=76)" &

        ovs-ofctl add-flow br-ovs "table=5, ip,ct_zone=80,ct_state=+trk+est actions=normal" &
        ovs-ofctl add-flow br-ovs "table=6, ip,ct_zone=79,ct_state=+trk+est actions=normal" &
        ovs-ofctl add-flow br-ovs "table=7, ip,ct_zone=78,ct_state=+trk+est actions=normal" &
        ovs-ofctl add-flow br-ovs "table=8, ip,ct_zone=76,ct_state=+trk+est actions=normal" &
        sleep 0.01

        ovs-ofctl del-flows br-ovs "table=5, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.1 actions=ct(table=1,zone=99)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.2 actions=ct(table=1,zone=99)" &
        
        ovs-ofctl del-flows br-ovs "table=6, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.3 actions=ct(table=2,zone=98)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.4 actions=ct(table=2,zone=98)" &

        ovs-ofctl del-flows br-ovs "table=7, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.5 actions=ct(table=3,zone=97)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.6 actions=ct(table=3,zone=97)" &

        ovs-ofctl del-flows br-ovs "table=8, ct_state=+est+trk" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.7 actions=ct(table=4,zone=96)" &
        ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.8 actions=ct(table=4,zone=96)" &

        ovs-ofctl add-flow br-ovs "table=1, ip,ct_zone=99,ct_state=+trk+est actions=normal" &
        ovs-ofctl add-flow br-ovs "table=2, ip,ct_zone=98,ct_state=+trk+est actions=normal" &
        ovs-ofctl add-flow br-ovs "table=3, ip,ct_zone=97,ct_state=+trk+est actions=normal" &
        ovs-ofctl add-flow br-ovs "table=4, ip,ct_zone=96,ct_state=+trk+est actions=normal" &

        sleep 0.01
    done
}

function run() {
    title "Test OVS CT TCP"
    config_vf ns0 $VF1 $REP1 $IP1
    config_vf ns1 $VF2 $REP2 $IP2
    config_vf ns2 $VF3 $REP3 $IP3
    config_vf ns3 $VF4 $REP4 $IP4
    config_vf ns4 $VF5 $REP5 $IP5
    config_vf ns5 $VF6 $REP6 $IP6
    config_vf ns6 $VF7 $REP7 $IP7
    config_vf ns7 $VF8 $REP8 $IP8

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


    ovs-ofctl del-flows br-ovs
    ovs-ofctl add-flow br-ovs arp,actions=normal
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.1 actions=ct(table=1,zone=99)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.2 actions=ct(table=1,zone=99)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.3 actions=ct(table=2,zone=98)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.4 actions=ct(table=2,zone=98)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.5 actions=ct(table=3,zone=97)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.6 actions=ct(table=3,zone=97)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.7 actions=ct(table=4,zone=96)"
    ovs-ofctl add-flow br-ovs "table=0, ip,ct_state=-trk,nw_src=7.7.7.8 actions=ct(table=4,zone=96)"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_state=+trk+new actions=ct(zone=99, commit),normal"
    ovs-ofctl add-flow br-ovs "table=1, ip,ct_zone=99,ct_state=+trk+est actions=normal"
    ovs-ofctl add-flow br-ovs "table=2, ip,ct_state=+trk+new actions=ct(zone=98, commit),normal"
    ovs-ofctl add-flow br-ovs "table=2, ip,ct_zone=98,ct_state=+trk+est actions=normal"
    ovs-ofctl add-flow br-ovs "table=3, ip,ct_state=+trk+new actions=ct(zone=97, commit),normal"
    ovs-ofctl add-flow br-ovs "table=3, ip,ct_zone=97,ct_state=+trk+est actions=normal"
    ovs-ofctl add-flow br-ovs "table=4, ip,ct_state=+trk+new actions=ct(zone=96, commit),normal"
    ovs-ofctl add-flow br-ovs "table=4, ip,ct_zone=96,ct_state=+trk+est actions=normal"
    ovs-ofctl add-flow br-ovs "table=5, ip,ct_state=+trk+new actions=ct(zone=80, commit),normal"
    ovs-ofctl add-flow br-ovs "table=6, ip,ct_state=+trk+new actions=ct(zone=79, commit),normal"
    ovs-ofctl add-flow br-ovs "table=7, ip,ct_state=+trk+new actions=ct(zone=78, commit),normal"
    ovs-ofctl add-flow br-ovs "table=8, ip,ct_state=+trk+new actions=ct(zone=76, commit),normal"

    ovs-ofctl dump-flows br-ovs --color

    echo "start stress test"
    ip netns exec ns1 iperf -s &
    sleep 1 
    ip netns exec ns0 iperf -t 0 -c $IP2 -P 16 &

    ip netns exec ns3 iperf -s &
    sleep 1
    ip netns exec ns2 iperf -t 0 -c $IP4 -P 16 &

    ip netns exec ns5 iperf -s &
    sleep 1
    ip netns exec ns4 iperf -t 0 -c $IP6 -P 16 &

    ip netns exec ns7 iperf -s &
    sleep 1
    ip netns exec ns6 iperf -t 0 -c $IP8 -P 16 &

    sleep 1
    ovs_dump_tc_flows --names
    ovs_dump_tc_flows --names | grep -q "ct(.*commit.*)" || err "Expected ct commit action"
}

cleanup
run
add_del_table &

# wait here until user press any key to stop
read -n 1
