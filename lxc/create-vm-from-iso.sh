
#!/bin/bash
function show_usage {
        echo "Usage:"
        echo "./create-vm-from-iso.sh {vm name} {root disk size in G} {iso path}"
        echo ""
        echo "example:"
        echo "./create-vm-from-iso.sh testvm 60 ~/ubuntu/iso/ubuntu-24.04.1-live-server-amd64.iso"
        echo ""
}

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        show_usage
        exit 1
fi

lxc init "$1" --empty --vm
lxc config set "$1" security.secureboot=false
lxc config device override "$1" root size="$2"GB
lxc config device add "$1" install-disk disk source="$3"

vga_viewer=$(dpkg -l | grep virt-viewer)
if [ -z "$vga_viewer" ]; then
        sudo apt install -y virt-viewer
fi

echo "After launching VGA client, press ESC to enter BIOS and select CD-ROM to boot the install ISO"
echo "After installation done, the install ISO will be removed automatically"
read -p "Press any key to launch VM with VGA"

lxc start "$1" --console=vga
lxc config device remove "$1" install-disk
