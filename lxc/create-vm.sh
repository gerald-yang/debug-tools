#!/bin/bash

if [ -z "$1" ] || [ "$1" = "-h" ]; then
        echo "Usage:"
        echo "  ./create-vm.sh {ubuntu series} {vm name} {cpu} {memory} {disk}"
        echo ""
        echo "Example:"
        echo "  ./create-vm.sh noble noble-vm 4 8 60"
	exit 0 
fi

lxc storage create "$2"-disk dir

lxc init ubuntu:"$1" "$2" --storage="$2"-disk --vm
lxc config set "$2" limits.cpu "$3"
lxc config set "$2" limits.memory "$4"GiB
lxc config set "$2" security.secureboot false
lxc config device set "$2" root size="$5"GiB
lxc start "$2"

echo "waiting for user to be created"
while true; do
        lxc exec "$2" -- /bin/bash -c "test -d /home/ubuntu/.ssh"
        if [ "$?" = "0" ]; then
                break
        else
                sleep 1
        fi
done
echo "done"

echo "setup ssh auth key"
IDPUB=$(cat ~/.ssh/id_rsa.pub)
lxc exec "$2" -- /bin/bash -c "echo $IDPUB > /home/ubuntu/.ssh/authorized_keys"
echo "done"
        
echo "searching container address"
INSTANCE_ID=0
for((i=0; i<100; i++)); do
        NAME=$(lxc list --format=json | jq -r .[$i].name)
        if [ "$NAME" = "$2" ]; then
                INSTANCE_ID="$i"
                break
        elif [ "$NAME" = "null" ]; then
                echo "can not find $2"
                exit 1
        fi
done
ADDR=$(lxc list --format=json | jq -r .["$INSTANCE_ID"].state.network.enp5s0.addresses[0].address)
echo "address: $ADDR"

echo "setup ssh agent"
eval $(ssh-agent -s)
agent_pid=$(ps aux | grep gerald | grep ssh-agent | grep -v grep | awk '{print $2}')
ssh-add

echo "Host $2" >> ~/.ssh/config
echo "  ForwardAgent yes" >> ~/.ssh/config
echo "  HostName $ADDR" >> ~/.ssh/config
echo "  User ubuntu" >> ~/.ssh/config
