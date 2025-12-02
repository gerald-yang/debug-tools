#!/bin/bash

if ! [ $(id -u) -eq 0 ]; then
        echo "run as root"
        exit -1
fi

if ! dpkg -s fio >/dev/null 2>&1; then
	        echo "install fio"
		        apt install fio -y
fi

DISK="testdisk"
FOLDER="mnt"

mkdir -p "$FOLDER"

if mountpoint -q "$FOLDER"; then
	        echo "umount $FOLDER"
		        umount "$FOLDER"
fi

rm -f "$DISK"
dd if=/dev/random of="$DISK" bs=1G count=2 oflag=direct
mkfs.ext4 "$DISK"
tune2fs -o journal_data "$DISK"

mount "$DISK" "$FOLDER"
fio --name=fiotest --rw=randwrite --bs=4k --runtime=3 --ioengine=libaio --iodepth=128 --numjobs=4 --filename="$FOLDER"/fiotest --filesize=1G --group_reporting
mount -o remount,ro "$DISK" "$FOLDER"
sync

umount "$FOLDER"
rm -f "$DISK"

echo ""
echo "check dmesg"
dmesg | tail -n 20
