#!/bin/bash
#
# Create a CentOS LXD container with a build toolchain, install our ssh key and
# add an ~/.ssh/config entry for it.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

GUEST_USER=root

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <centos series> <name> <disk GB> [configure: yes|no]
	  ${0##*/} -c <name> [centos series]   configure an existing container only
	  ${0##*/} -h                          show this help

	configure: set up the ssh/gpg keys and clone the tools (default: no)

	Example:
	  ${0##*/} images:centos/8-Stream centos-c 30 yes
	EOU
}

config_container() {
	local name="$1" series="$2" addr

	instance_exists "$name" || die "container $name does not exist"

	# CentOS images ship without a DHCP lease; keep asking until the
	# interface comes up, otherwise every yum call below fails.
	wait_for 120 "network in $name" lxc exec "$name" -- dhclient eth0

	log "installing packages"
	lxc exec "$name" -- yum -y update
	lxc exec "$name" -- yum -y install \
		wget git openssh-server bash-completion tar libffi-devel

	# centos7 predates python3-virtualenv and needs SCL for a modern gcc.
	if [ "$series" = "centos7" ]; then
		lxc exec "$name" -- yum -y install \
			epel-release dnf python-virtualenv centos-release-scl
		lxc exec "$name" -- yum-config-manager --enable rhel-server-rhscl-7-rpms
		lxc exec "$name" -- yum -y install devtoolset-8
		lxc exec "$name" -- /bin/bash -c \
			"echo 'scl enable devtoolset-8 bash' > /root/enable-devtoolset-8"
	else
		lxc exec "$name" -- yum -y install python3-virtualenv
		lxc exec "$name" -- yum -y groupinstall "Development Tools"
	fi

	log "starting sshd"
	lxc exec "$name" -- systemctl enable --now sshd
	wait_for 60 "sshd in $name" lxc exec "$name" -- systemctl is-active sshd

	push_ssh_key "$name" "$GUEST_USER"

	addr=$(wait_for_addr "$name")
	ssh_config_add "$name" "$addr" "$GUEST_USER"
	check_ssh_agent

	copy_dev_config "$addr" "$GUEST_USER"
	remote_ssh "$name" git clone https://github.com/gerald-yang/debug-tools || \
		warn "git clone debug-tools failed"

	log "container $name ready:  ssh $name"
}

need_cmd lxc jq

case "${1:-}" in
	-h|--help|"") usage; exit 0 ;;
	-c)
		[ -n "${2:-}" ] || die "enter the container name to configure"
		# The series decides which toolchain to install, so it has to be
		# passed here too - the original script read an unset variable.
		config_container "$2" "${3:-}"
		exit 0
		;;
esac

[ "$#" -ge 3 ] || { echo "error: expected at least 3 arguments, got $#" >&2; usage; exit 1; }

CENTOS_SERIES="$1"
CONTAINER_NAME="$2"
STORAGE_SIZE="$3"
NEED_CONFIG="${4:-no}"

[[ "$STORAGE_SIZE" =~ ^[0-9]+$ ]] || die "disk size must be a number of GB, got '$STORAGE_SIZE'"
if instance_exists "$CONTAINER_NAME"; then die "instance $CONTAINER_NAME already exists"; fi

log "creating storage pool $CONTAINER_NAME-disk (${STORAGE_SIZE}GB, btrfs)"
lxc storage create "$CONTAINER_NAME-disk" btrfs size="${STORAGE_SIZE}GB" || die "create storage failed"

log "launching container $CONTAINER_NAME from $CENTOS_SERIES"
lxc launch "$CENTOS_SERIES" "$CONTAINER_NAME" --storage "$CONTAINER_NAME-disk" || \
	die "launch $CONTAINER_NAME failed"

if [ "$NEED_CONFIG" = "yes" ]; then
	config_container "$CONTAINER_NAME" "$CENTOS_SERIES"
else
	log "container $CONTAINER_NAME launched; run '${0##*/} -c $CONTAINER_NAME $CENTOS_SERIES' to configure it"
fi
