
#!/bin/bash
function show_usage {
        echo "Usage:"
        echo "./create-vm-from-iso.sh {vm name} {cpu} {memory in G} {root disk size in G} {iso path}"
        echo ""
        echo "example:"
        echo "./create-vm-from-iso.sh testvm 4 16 60 ~/ubuntu/iso/ubuntu-24.04.1-live-server-amd64.iso"
        echo ""
}

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
        show_usage
        exit 1
fi

VM_NAME="$1"
CPUS="$2"
MEM="$3"
DISK_SIZE="$4"
ISO_PATH="$5"

lxc init "$VM_NAME" --empty --vm
lxc config set "$VM_NAME" limits.cpu "$CPUS"
lxc config set "$VM_NAME" limits.memory "$MEM"GiB
lxc config set "$VM_NAME" security.secureboot=false
lxc config device override "$VM_NAME" root size="$DISK_SIZE"GB
lxc config device add "$VM_NAME" install-disk disk source="$ISO_PATH"

vga_viewer=$(dpkg -l | grep virt-viewer)
if [ -z "$vga_viewer" ]; then
        sudo apt install -y virt-viewer
fi

echo "After launching VGA client, press ESC to enter BIOS and select CD-ROM to boot the install ISO"
echo "After installation done, the install ISO will be removed automatically"
read -p "Press any key to launch VM with VGA"

lxc start "$VM_NAME" --console=vga

echo "searching vm address"
INSTANCE_ID=0
for((i=0; i<100; i++)); do
        NAME=$(lxc list --format=json | jq -r .[$i].name)
        if [ "$NAME" = "$VM_NAME" ]; then
                INSTANCE_ID="$i"
                break
        elif [ "$NAME" = "null" ]; then
                echo "can not find $VM_NAME"
                exit 1
        fi
done
ADDR=$(lxc list --format=json | jq -r .["$INSTANCE_ID"].state.network.enp5s0.addresses[0].address)
echo "address: $ADDR"

echo "" >> ~/.ssh/config
echo "Host $VM_NAME" >> ~/.ssh/config
echo "  ForwardAgent yes" >> ~/.ssh/config
echo "  HostName $ADDR" >> ~/.ssh/config
echo "  User gerald" >> ~/.ssh/config

lxc config device remove "$VM_NAME" install-disk
