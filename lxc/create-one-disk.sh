#!/bin/bash
#
# Create a block storage volume and optionally attach it to an instance.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <disk name> <disk size GB> [instance name] [pool]
	  ${0##*/} -h    show this help

	pool defaults to "default"; the instance name is optional - leave it out
	to create the volume without attaching it.

	Example:
	  ${0##*/} test-disk 60
	  ${0##*/} test-disk 60 testvm
	EOU
}

need_cmd lxc

case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ "$#" -ge 2 ] || { echo "error: expected at least 2 arguments, got $#" >&2; usage; exit 1; }

DISK_NAME="$1"
DISK_SIZE="$2"
INSTANCE="${3:-}"
POOL="${4:-default}"

[[ "$DISK_SIZE" =~ ^[0-9]+$ ]] || die "disk size must be a number of GB, got '$DISK_SIZE'"
lxc storage show "$POOL" >/dev/null 2>&1 || die "storage pool $POOL does not exist"

log "creating volume $DISK_NAME (${DISK_SIZE}GiB) in pool $POOL"
lxc storage volume create "$POOL" "$DISK_NAME" size="${DISK_SIZE}GiB" --type block

if [ -n "$INSTANCE" ]; then
	instance_exists "$INSTANCE" || die "instance $INSTANCE does not exist"
	log "attaching $DISK_NAME to $INSTANCE"
	lxc config device add "$INSTANCE" "$DISK_NAME" disk pool="$POOL" source="$DISK_NAME"
fi

log "done"
