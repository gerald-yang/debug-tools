#!/bin/bash

if [ -z "$1" ] || [ "$1" = "-h" ]; then
        echo "Usage:"
        echo "  ./create-vm.sh {ubuntu series} {vm name} {cpu} {memory} {disk} {create storage} {from daily}"
        echo ""
        echo "Example:"
        echo "  ./create-vm.sh noble noble-vm 4 8 60 yes no"
	exit 0 
fi

SERIES="$1"
VM_NAME="$2"
CPUS="$3"
MEM="$4"
DISK="$5"
CREATE_DISK="$6"
DAILY_BUILD="$7"

if [ "$CREATE_DISK" = "yes" ]; then
        lxc storage create "$VM_NAME"-disk dir
fi

# list all images in ubuntu: or ubuntu-daily:
# lxc image list ubuntu:
# lxc image list ubuntu-daily:

if [ "$DAILY_BUILD" == "yes" ]; then
        lxc init ubuntu-daily:"$SERIES" "$VM_NAME" --vm
else
        lxc init ubuntu:"$SERIES" "$VM_NAME" --vm
fi
lxc config set "$VM_NAME" limits.cpu "$CPUS"
lxc config set "$VM_NAME" limits.memory "$MEM"GiB
lxc config set "$VM_NAME" security.secureboot false
## old lxc uses "set" instead of "override"
#lxc config device set "$VM_NAME" root size="$DISK"GiB
lxc config device override "$VM_NAME" root size="$DISK"GiB
lxc start "$VM_NAME"

echo "waiting for user to be created"
while true; do
        lxc exec "$VM_NAME" -- /bin/bash -c "test -d /home/ubuntu/.ssh"
        if [ "$?" = "0" ]; then
                break
        else
                sleep 1
        fi
done
echo "done"

echo "setup ssh auth key"
IDPUB=$(cat ~/.ssh/id_rsa.pub)
lxc exec "$VM_NAME" -- /bin/bash -c "echo $IDPUB > /home/ubuntu/.ssh/authorized_keys"
echo "done"
        
echo "searching container address"
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

echo "setup ssh agent"
eval $(ssh-agent -s)
agent_pid=$(ps aux | grep gerald | grep ssh-agent | grep -v grep | awk '{print $2}')
ssh-add

echo "" >> ~/.ssh/config
echo "Host $2" >> ~/.ssh/config
echo "  ForwardAgent yes" >> ~/.ssh/config
echo "  HostName $ADDR" >> ~/.ssh/config
echo "  User ubuntu" >> ~/.ssh/config
