#!/bin/bash
#
# Create an empty LXD VM and install it interactively from an ISO over a VGA
# console.
set -euo pipefail

. "$(dirname "$(readlink -f "$0")")/lib/common.sh"

usage() {
	cat <<-EOU
	Usage:
	  ${0##*/} <vm name> <cpus> <memory GB> <root disk GB> <iso path> [guest user]
	  ${0##*/} -h    show this help

	guest user defaults to \$USER ($USER); it is only used for the
	~/.ssh/config entry written after the install finishes.

	Example:
	  ${0##*/} testvm 4 16 60 ~/ubuntu/iso/ubuntu-24.04.1-live-server-amd64.iso
	EOU
}

need_cmd lxc jq

case "${1:-}" in -h|--help|"") usage; exit 0 ;; esac
[ "$#" -ge 5 ] || { echo "error: expected at least 5 arguments, got $#" >&2; usage; exit 1; }

VM_NAME="$1"
CPUS="$2"
MEM="$3"
DISK_SIZE="$4"
ISO_PATH="$5"
GUEST_USER="${6:-$USER}"

for n in "$CPUS" "$MEM" "$DISK_SIZE"; do
	[[ "$n" =~ ^[0-9]+$ ]] || die "cpus, memory and disk must be numbers, got '$n'"
done
[ -r "$ISO_PATH" ] || die "cannot read ISO $ISO_PATH"
# lxc needs an absolute path for a disk device source.
ISO_PATH=$(readlink -f "$ISO_PATH")
if instance_exists "$VM_NAME"; then die "instance $VM_NAME already exists"; fi

if ! command -v virt-viewer >/dev/null 2>&1; then
	log "installing virt-viewer for the VGA console"
	sudo apt install -y virt-viewer
fi

log "creating empty VM $VM_NAME"
lxc init --empty --vm "$VM_NAME"
lxc config set "$VM_NAME" limits.cpu "$CPUS"
lxc config set "$VM_NAME" limits.memory "${MEM}GiB"
lxc config set "$VM_NAME" security.secureboot false
lxc config device override "$VM_NAME" root size="${DISK_SIZE}GiB"
lxc config device add "$VM_NAME" install-disk disk source="$ISO_PATH"

# The install disk must go away whichever way we leave, or the VM boots the
# installer again on the next start.
cleanup_iso() {
	lxc config device remove "$VM_NAME" install-disk >/dev/null 2>&1 || true
}
trap cleanup_iso EXIT

cat <<-EOM

	Press ESC in the VGA window to enter the BIOS, then boot from the CD-ROM
	to start the installer. Close the console when the install has finished;
	the install ISO is detached automatically.

EOM
read -r -n 1 -s -p "Press any key to launch the VM with a VGA console... "
echo

lxc start "$VM_NAME" --console=vga

ADDR=$(wait_for_addr "$VM_NAME")
ssh_config_add "$VM_NAME" "$ADDR" "$GUEST_USER"
check_ssh_agent

log "VM $VM_NAME ready:  ssh $VM_NAME"
