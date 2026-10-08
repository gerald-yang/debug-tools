#!/bin/bash
#
# Stop and delete an LXD instance, plus the matching <name>-disk storage pool
# and its ~/.ssh/config entry.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <instance name> [-y]
	  ${0##*/} -h    show this help

	-y   do not ask for confirmation
	EOU
}

need_cmd lxc

case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac

NAME="$1"
ASSUME_YES="${2:-}"
POOL="$NAME-disk"

instance_exists "$NAME" || die "instance $NAME does not exist"

if [ "$ASSUME_YES" != "-y" ]; then
	read -r -p "Delete instance $NAME and storage pool $POOL? [y/N] " reply
	case "$reply" in [yY]|[yY][eE][sS]) ;; *) log "aborted"; exit 0 ;; esac
fi

log "stopping $NAME"
lxc stop --force "$NAME" 2>/dev/null || true

log "deleting $NAME"
lxc delete --force "$NAME" || die "delete $NAME failed"

# The pool is only ours if create-lxc.sh made it; a shared pool has a different
# name, so a missing pool here is normal rather than an error.
if lxc storage show "$POOL" >/dev/null 2>&1; then
	log "deleting storage pool $POOL"
	lxc storage delete "$POOL" || die "delete storage $POOL failed"
else
	log "no storage pool named $POOL, skipping"
fi

if grep -qE "^[[:space:]]*Host[[:space:]]+${NAME}[[:space:]]*$" "$HOME/.ssh/config" 2>/dev/null; then
	log "removing ~/.ssh/config entry for $NAME"
	awk -v h="$NAME" '$1 == "Host" { skip = ($2 == h && NF == 2) } !skip' \
		"$HOME/.ssh/config" > "$HOME/.ssh/config.tmp"
	mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
fi

log "$NAME deleted"
