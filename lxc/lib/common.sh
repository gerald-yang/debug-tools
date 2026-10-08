#!/bin/bash
# Shared helpers for the lxc/ scripts. Source it, do not execute it:
#   . "$(dirname "$(readlink -f "$0")")/lib/common.sh"

# Refuse to run as a program - every function here needs the caller's shell.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	echo "common.sh is a library, source it instead of running it" >&2
	exit 1
fi

log() { echo "==> $*"; }
warn() { echo "warning: $*" >&2; }
die() { echo "error: $*" >&2; exit 1; }

# need_cmd CMD...  - abort unless every CMD is on PATH
need_cmd() {
	local c
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 || die "$c is required but not installed"
	done
}

# instance_exists NAME
instance_exists() {
	lxc info "$1" >/dev/null 2>&1
}

# instance_addr NAME - first global IPv4 of any non-loopback interface.
# Interface-name agnostic, so it works for both containers (eth0) and VMs
# (enp5s0), which change name across releases.
instance_addr() {
	lxc list "$1" --format=json 2>/dev/null | jq -r --arg n "$1" '
		.[] | select(.name == $n) | .state.network // {}
		| to_entries[] | select(.key != "lo")
		| .value.addresses[]?
		| select(.family == "inet" and .scope == "global")
		| .address' | head -n 1
}

# wait_for TIMEOUT DESCRIPTION COMMAND...  - poll COMMAND until it succeeds
wait_for() {
	local timeout="$1" what="$2"; shift 2
	local deadline=$((SECONDS + timeout))

	log "waiting for $what (up to ${timeout}s)"
	while ! "$@" >/dev/null 2>&1; do
		[ "$SECONDS" -lt "$deadline" ] || die "timed out waiting for $what"
		sleep 2
	done
	log "$what ready"
}

# wait_for_addr NAME [TIMEOUT] - block until the instance has an IPv4, echo it
wait_for_addr() {
	local name="$1" timeout="${2:-300}"
	local deadline=$((SECONDS + timeout)) addr=""

	log "waiting for $name to get an address (up to ${timeout}s)" >&2
	while :; do
		addr=$(instance_addr "$name")
		[ -z "$addr" ] || break
		[ "$SECONDS" -lt "$deadline" ] || die "timed out waiting for $name address"
		sleep 2
	done
	log "$name address: $addr" >&2
	echo "$addr"
}

# wait_for_path NAME PATH [TIMEOUT] - block until PATH exists inside the instance
wait_for_path() {
	local name="$1" path="$2" timeout="${3:-300}"
	wait_for "$timeout" "$path in $name" lxc exec "$name" -- test -e "$path"
}

# push_ssh_key NAME USER [PUBKEY] - install our public key as an authorized key
push_ssh_key() {
	local name="$1" user="$2" pubkey="${3:-$HOME/.ssh/id_rsa.pub}"
	local home

	[ -r "$pubkey" ] || die "public key $pubkey not found"
	if [ "$user" = "root" ]; then home=/root; else home="/home/$user"; fi

	log "installing $pubkey for $user@$name"
	# Feed the key on stdin so its content is never re-parsed by a shell.
	lxc exec "$name" -- /bin/bash -c "
		set -e
		mkdir -p '$home/.ssh'
		cat >> '$home/.ssh/authorized_keys'
		sort -u -o '$home/.ssh/authorized_keys' '$home/.ssh/authorized_keys'
		chmod 700 '$home/.ssh'
		chmod 600 '$home/.ssh/authorized_keys'
		chown -R '$user' '$home/.ssh'
	" < "$pubkey"
}

# ssh_config_add HOST ADDR USER - add/replace the ~/.ssh/config entry for HOST
ssh_config_add() {
	local host="$1" addr="$2" user="$3"
	local cfg="$HOME/.ssh/config"

	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	touch "$cfg"

	# Drop any previous block for this host so repeated runs do not stack up
	# stale entries (the first match wins in ssh_config, so a stale block
	# would otherwise shadow the new address).
	if grep -qE "^[[:space:]]*Host[[:space:]]+${host}[[:space:]]*$" "$cfg"; then
		log "replacing existing ~/.ssh/config entry for $host"
		# Squeeze the blank runs left behind too, so repeated runs do
		# not grow the file one blank line at a time.
		awk -v h="$host" '
			$1 == "Host" { skip = ($2 == h && NF == 2) }
			skip { next }
			/^[[:space:]]*$/ { blank++; next }
			{ if (blank && NR > blank) print ""; blank = 0; print }
		' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
	fi

	log "adding ~/.ssh/config entry for $host -> $addr"
	cat >> "$cfg" <<-EOC

	Host $host
	  HostName $addr
	  User $user
	  ForwardAgent yes
	  StrictHostKeyChecking no
	  UserKnownHostsFile /dev/null
	EOC
	chmod 600 "$cfg"
}

# check_ssh_agent - warn if agent forwarding will not work
# An `eval $(ssh-agent -s)` here would die with the script, so only report.
check_ssh_agent() {
	if [ -z "${SSH_AUTH_SOCK:-}" ] || ! ssh-add -l >/dev/null 2>&1; then
		warn "no usable ssh-agent; 'ForwardAgent yes' will do nothing."
		warn "run in your shell:  eval \$(ssh-agent -s) && ssh-add"
	fi
}

# remote_ssh HOST CMD... - run a command on a freshly created instance
remote_ssh() {
	local host="$1"; shift
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	    -o LogLevel=ERROR "$host" "$@"
}

# copy_dev_config ADDR USER - copy ssh keys, gpg and git config to the instance
copy_dev_config() {
	local addr="$1" user="$2"
	local scp_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
	local item

	log "copying developer config to $user@$addr"
	for item in ~/.ssh/id_rsa ~/.ssh/id_rsa.pub; do
		if [ -e "$item" ]; then
			scp "${scp_opts[@]}" "$item" "$user@$addr:.ssh/" || warn "copying $item failed"
		fi
	done
	for item in ~/.gnupg ~/.gitconfig; do
		if [ -e "$item" ]; then
			scp -r "${scp_opts[@]}" "$item" "$user@$addr:" || warn "copying $item failed"
		fi
	done
}
