#!/bin/bash

usage() {
	echo ""
	echo "Usage:"
	echo "create-lxc.sh UBUNT_SERIES CONTAINER_NAME STORAGE_SIZE [NEED_CONFIG]"
	echo "create-lxc.sh -c CONTAINER_NAME"
	echo ""
	echo "NEED_CONFIG: yes or no(default)"
	echo "             setup ssh/gpg key and copy/clone tools"
	echo ""
}

config_container() {
	echo "waiting for user to be created"
	while true; do
		lxc exec "$1" -- /bin/bash -c "test -d /home/ubuntu/.ssh"
		if [ "$?" = "0" ]; then
			break
		else
			sleep 1
		fi
	done
	echo "done"

	echo "setup ssh auth"
	IDPUB=$(cat ~/.ssh/id_rsa.pub)
	lxc exec "$1" -- /bin/bash -c "echo $IDPUB > /home/ubuntu/.ssh/authorized_keys"
	echo "done"
	
	echo "searching container address"
	INSTANCE_ID=0
	for((i=0; i<100; i++)); do
		NAME=$(lxc list --format=json | jq -r .[$i].name)
		if [ "$NAME" = "$1" ]; then
			INSTANCE_ID="$i"
			break
		elif [ "$NAME" = "null" ]; then
			echo "can not find $1"
			exit 1
		fi
	done
	ADDR=$(lxc list --format=json | jq -r .["$INSTANCE_ID"].state.network.eth0.addresses[0].address)
	echo "address: $ADDR"

	echo "copy configs"
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa ubuntu@"$ADDR":~/.ssh/
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa.pub ubuntu@"$ADDR":~/.ssh/
	scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.gnupg ubuntu@"$ADDR":~/
	scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.gitconfig ubuntu@"$ADDR":~/
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/bin/lsftp ubuntu@"$ADDR":~/
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/vim
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/ceph-tools
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/debug-tools
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/brendangregg/flamegraph
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" sudo apt install linux-tools-common
}

if [ "$1" = "-c" ]; then
        if [ -z "$2" ]; then
                echo "enter container name to be configured"
                exit -1
        fi
        config_container "$2"
        exit 0
fi

if [ -z "$1" ]; then
	echo "Wrong parameter 1"
	usage
	exit 1
fi

if [ -z "$2" ]; then
	echo "Wrong parameter 2"
	usage
	exit 1
fi

if [ -z "$3" ]; then
	echo "Wrong parameter 3"
	usage
	exit 1
fi

if [ -z "$3" ]; then
	echo "Wrong parameter 3"
	usage
	exit 1
fi

UBUNTU_SERIES="$1"
CONTAINER_NAME="$2"
STORAGE_SIZE="$3"
NEED_CONFIG="$4"

echo "creating storage $CONTAINER_NAME-disk"
lxc storage create "$CONTAINER_NAME"-disk btrfs size="$STORAGE_SIZE"GB
if [ "$?" != "0" ]; then
	echo "create storage failed"
	exit 1
fi
echo "done"

echo "launching container $CONTAINER_NAME"
lxc launch "$UBUNTU_SERIES"-image "$CONTAINER_NAME" --storage="$CONTAINER_NAME"-disk
if [ "$?" != "0" ]; then
	echo "launch $CONTAINER_NAME failed"
	exit 1
fi
echo "done"

if [ "$NEED_CONFIG" = "yes" ]; then
	config_container "$CONTAINER_NAME"
fi
