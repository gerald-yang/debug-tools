#!/bin/bash

NUM_OSD=3
NUM_MON=1

if [ "$1" = "-o" ]; then
	OSD="$NUM_OSD" MON="$NUM_MON" MDS=1 MGR=1 RGW=1 ../src/vstart.sh --rgw_port 7480 --rgw_frontend civetweb -b
elif [ "$1" = "-k" ]; then
	OSD="$NUM_OSD" MON="$NUM_MON" MDS=1 MGR=1 RGW=1 ../src/vstart.sh -n -k --rgw_port 7480 --rgw_frontend civetweb -b
elif [ "$1" = "--crimson" ]; then
	MDS=0 MGR=1 OSD=3 MON=1 ../src/vstart.sh -n --without-dashboard --memstore -X -o "memstore_device_bytes=4294967296" --nolockdep --crimson --nodaemon --redirect-output
else
	OSD="$NUM_OSD" MON="$NUM_MON" MDS=1 MGR=1 RGW=1 ../src/vstart.sh -n --rgw_port 7480 --rgw_frontend civetweb -b
fi
