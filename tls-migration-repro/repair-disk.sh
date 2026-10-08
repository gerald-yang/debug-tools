#!/bin/bash
# Offline repair for the test guest's disk image.
#
#   repair-disk.sh [-y] [IMAGE]
#
#   -y     actually repair (default is a read-only check)
#
# WHEN YOU NEED THIS
# ------------------
# Symptom: the VM launches, QEMU stays alive, RSS settles around 3-4 GiB, the
# guest burns ~0 CPU, and the serial console returns ZERO bytes -- con.py fails
# with "no shell prompt" no matter how often you retry.
#
# Cause: the guest's root filesystem was left dirty (QEMU SIGKILLed while the
# guest was still running). systemd cannot bring up the /boot and /boot/efi
# device/mount units, so it drops to emergency mode. Ubuntu cloud images have
# the root account locked, so sulogin cannot open a shell and the console goes
# permanently silent.
#
# This script maps the qcow2 with qemu-nbd and fsck's every partition.
# ALL TEST VMs MUST BE STOPPED FIRST.
set -u

YES=0
while getopts "y" o; do
  case "$o" in
    y) YES=1 ;;
    *) echo "usage: $0 [-y] [IMAGE]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
IMG=${1:-/home/ubuntu/testvm.img}
NBD=${NBD:-/dev/nbd0}

[ -f "$IMG" ] || { echo "no such image: $IMG" >&2; exit 1; }

live=$(ps -eo comm= -o args= | awk '$1 ~ /^qemu-system/ {n++} END {print n+0}')
if [ "$live" -gt 0 ]; then
  echo "REFUSING: $live QEMU process(es) still running - stop them first:" >&2
  ps -eo pid,args | grep -- '-name vm' | grep -v grep >&2
  echo "    sudo ./cleanup.sh" >&2
  exit 1
fi

cleanup() { qemu-nbd -d "$NBD" >/dev/null 2>&1 || true; }
trap cleanup EXIT

modprobe nbd max_part=16 2>/dev/null || true
qemu-nbd -d "$NBD" >/dev/null 2>&1 || true
qemu-nbd -c "$NBD" "$IMG" || { echo "could not attach $IMG to $NBD" >&2; exit 1; }
sleep 2

echo "=== partitions in $IMG ==="
lsblk -o NAME,SIZE,FSTYPE,LABEL "$NBD"
echo

rc=0
for p in "$NBD"p*; do
  [ -b "$p" ] || continue
  t=$(blkid -o value -s TYPE "$p" 2>/dev/null || true)
  l=$(blkid -o value -s LABEL "$p" 2>/dev/null || true)
  case "$t" in
    ext2|ext3|ext4)
      echo "--- e2fsck ${p} (${l:-no label})"
      if [ "$YES" = "1" ]; then e2fsck -f -y "$p"; else e2fsck -f -n "$p"; fi
      [ $? -gt 1 ] && rc=1 ;;
    vfat)
      echo "--- fsck.vfat ${p} (${l:-no label})"
      if [ "$YES" = "1" ]; then fsck.vfat -w -a "$p"; else fsck.vfat -n "$p"; fi
      [ $? -gt 1 ] && rc=1 ;;
    *)
      echo "--- skipping ${p} (type '${t:-none}')" ;;
  esac
  echo
done

if [ "$YES" = "1" ]; then
  echo "repair pass complete. Re-run without -y to confirm the image is clean."
else
  echo "READ-ONLY CHECK ONLY. If errors were reported above, repair with:"
  echo "    sudo ./repair-disk.sh -y $IMG"
fi
exit $rc
