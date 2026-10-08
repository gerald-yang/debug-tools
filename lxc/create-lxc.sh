#!/bin/bash
#
# Create an Ubuntu LXD container, install our ssh key and add an ~/.ssh/config
# entry for it.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

GUEST_USER=ubuntu

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <series> <name> <disk GB> <create storage: yes|no> <from daily: yes|no>
	  ${0##*/} -c <name>     configure an existing container only
	  ${0##*/} -h            show this help

	Example:
	  ${0##*/} noble noble-c 30 yes no
	EOU
}

config_container() {
	local name="$1" addr

	instance_exists "$name" || die "container $name does not exist"

	# cloud-init creates the ubuntu user's .ssh late; wait for it so the
	# authorized_keys we write is not clobbered afterwards.
	wait_for_path "$name" "/home/$GUEST_USER/.ssh"
	push_ssh_key "$name" "$GUEST_USER"

	addr=$(wait_for_addr "$name")
	ssh_config_add "$name" "$addr" "$GUEST_USER"
	check_ssh_agent

	copy_dev_config "$addr" "$GUEST_USER"
	remote_ssh "$name" git clone https://github.com/gerald-yang/vim || \
		warn "git clone vim failed"
	#remote_ssh "$name" git clone https://github.com/gerald-yang/debug-tools
	#remote_ssh "$name" git clone https://github.com/brendangregg/flamegraph

	log "container $name ready:  ssh $name"
}

need_cmd lxc jq

case "${1:-}" in
	-h|--help|"") usage; exit 0 ;;
	-c)
		[ -n "${2:-}" ] || die "enter the container name to configure"
		config_container "$2"
		exit 0
		;;
esac

[ "$#" -eq 5 ] || { echo "error: expected 5 arguments, got $#" >&2; usage; exit 1; }

SERIES="$1"
NAME="$2"
DISK="$3"
CREATE_DISK="$4"
FROM_DAILY="$5"

[ "$CREATE_DISK" = "yes" ] || [ "$CREATE_DISK" = "no" ] || die "create storage must be yes or no"
[ "$FROM_DAILY" = "yes" ] || [ "$FROM_DAILY" = "no" ] || die "from daily must be yes or no"
if instance_exists "$NAME"; then die "instance $NAME already exists"; fi

launch_args=()
if [ "$CREATE_DISK" = "yes" ]; then
	[[ "$DISK" =~ ^[0-9]+$ ]] || die "disk size must be a number of GB, got '$DISK'"
	log "creating storage pool $NAME-disk (${DISK}GB, zfs)"
	lxc storage create "$NAME-disk" zfs size="${DISK}GB" || die "create storage failed"
	launch_args+=(--storage "$NAME-disk")
fi

if [ "$FROM_DAILY" = "yes" ]; then IMAGE="ubuntu-daily:$SERIES"; else IMAGE="ubuntu:$SERIES"; fi

log "launching container $NAME from $IMAGE"
lxc launch "$IMAGE" "$NAME" "${launch_args[@]}" || die "launch $NAME failed"

config_container "$NAME"
