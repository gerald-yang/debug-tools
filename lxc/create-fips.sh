#!/bin/bash

if [ -z "$1" ]; then
        echo "please enter your ubuntu pro token"
        exit -1
fi

lxc launch ubuntu:focal fips --vm -c security.secureboot=false -c limits.cpu=8 -c limits.memory=16GiB

echo "waiting for user to be created"
while true; do
        lxc exec fips -- /bin/bash -c "test -d /home/ubuntu/.ssh"
        if [ "$?" = "0" ]; then
                break
        else
                sleep 1
        fi
done
echo "done"

echo "setup ssh auth key"
IDPUB=$(cat ~/.ssh/id_rsa.pub)
lxc exec fips -- /bin/bash -c "echo $IDPUB > /home/ubuntu/.ssh/authorized_keys"
echo "done"
        
echo "searching container address"
INSTANCE_ID=0
for((i=0; i<100; i++)); do
        NAME=$(lxc list --format=json | jq -r .[$i].name)
        if [ "$NAME" = fips ]; then
                INSTANCE_ID="$i"
                break
        elif [ "$NAME" = "null" ]; then
                echo "can not find fips"
                exit 1
        fi
done
ADDR=$(lxc list --format=json | jq -r .["$INSTANCE_ID"].state.network.enp5s0.addresses[0].address)
echo "address: $ADDR"

echo "setup ssh agent"
eval $(ssh-agent -s)
agent_pid=$(ps aux | grep gerald | grep ssh-agent | grep -v grep | awk '{print $2}')
ssh-add

echo "Host fips" > ~/.ssh/config
echo "  ForwardAgent yes" >> ~/.ssh/config
echo "  HostName $ADDR" >> ~/.ssh/config
echo "  User ubuntu" >> ~/.ssh/config

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fips sudo pro attach "$1"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fips sudo pro enable fips-updates

#ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fips sudo apt purge -y linux-headers-5.4.0-1114-kvm linux-headers-kvm linux-image-5.4.0-1100-fips linux-image-5.4.0-1114-kvm linux-image-kvm linux-kvm linux-kvm-headers-5.4.0-1114 linux-modules-5.4.0-1114-kvm
