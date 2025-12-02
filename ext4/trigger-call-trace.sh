#!/bin/bash

if ! [ $(id -u) -eq 0 ]; then
        echo "run as root"
        exit -1
fi

DISK="$1"
FOLDER="$2"

if [ -z "$DISK" ] || [ -z "$FOLDER" ]; then
        echo "Usage:"
        echo "./trigger-ext4-call-trace.sh <ext4 disk> <mount folder>"
        exit -1
fi

if mountpoint -q "$FOLDER"; then
        echo "umount $FOLDER"
        umount "$FOLDER"
fi

journal_data=$(tune2fs -l "$DISK" | grep journal_data)
if [ -z "$journal_data" ]; then
        echo "journal_data not set, set it"
        tune2fs -o journal_data "$DISK"
fi

if ! dpkg -s fio >/dev/null 2>&1; then
	echo "install fio"
	apt install fio -y
fi

mount "$DISK" "$FOLDER"
fio --name=fiotest --rw=randwrite --bs=4k --runtime=3 --ioengine=libaio --iodepth=128 --numjobs=4 --filename="$FOLDER"/fiotest --filesize=1G --group_reporting
mount -o remount,ro "$DISK" "$FOLDER"
sync

echo ""
echo "check dmesg"
