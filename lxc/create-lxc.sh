#!/bin/bash

usage() {
	echo ""
	echo "Usage:"
	echo "create-lxc.sh UBUNT_SERIES CONTAINER_NAME STORAGE_SIZE DOWNLOAD_IMAGE [NEED_CONFIG] [NEED_CREATE_STORAGE]"
	echo "create-lxc.sh -c CONTAINER_NAME"
	echo ""
	echo "NEED_CONFIG: yes or no(default)"
	echo "             setup ssh/gpg key and copy/clone tools"
        echo ""
        echo "Example:"
        echo "./create-lxc.sh noble noble 30 yes yes yes"
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

        echo "setup ssh agent"
        eval $(ssh-agent -s)
        agent_pid=$(ps aux | grep gerald | grep ssh-agent | grep -v grep | awk '{print $2}')
        ssh-add

	echo "copy configs"
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa ubuntu@"$ADDR":~/.ssh/
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa.pub ubuntu@"$ADDR":~/.ssh/
	scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.gnupg ubuntu@"$ADDR":~/
	scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.gitconfig ubuntu@"$ADDR":~/
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/bin/lsftp ubuntu@"$ADDR":~/
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/vim
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/lvim
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/debug-tools
	#ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/brendangregg/flamegraph
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

if [ -z "$4" ]; then
	echo "Wrong parameter 4"
	usage
	exit 1
fi

UBUNTU_SERIES="$1"
CONTAINER_NAME="$2"
STORAGE_SIZE="$3"
DOWNLOAD_IMAGE="$4"

if [ -z "$5" ]; then
        NEED_CONFIG="no"
else
        NEED_CONFIG="$5"
fi

if [ -z "$6" ]; then
        CREATE_STORAGE="no"
else
        CREATE_STORAGE="$6"
fi

if [ "$CREATE_STORAGE" = "yes" ]; then
        echo "creating storage $CONTAINER_NAME-disk"
        lxc storage create "$CONTAINER_NAME"-disk btrfs size="$STORAGE_SIZE"GB
        if [ "$?" != "0" ]; then
	        echo "create storage failed"
	        exit 1
        fi
        echo "done"
fi

echo "launching container $CONTAINER_NAME"
if [ "$DOWNLOAD_IMAGE" = "yes" ]; then
        lxc launch ubuntu:"$UBUNTU_SERIES" "$CONTAINER_NAME" --storage="$CONTAINER_NAME"-disk
else
        lxc launch "$UBUNTU_SERIES"-image "$CONTAINER_NAME" --storage="$CONTAINER_NAME"-disk
fi
if [ "$?" != "0" ]; then
	echo "launch $CONTAINER_NAME failed"
	exit 1
fi
echo "done"

if [ "$NEED_CONFIG" = "yes" ]; then
	config_container "$CONTAINER_NAME"
fi
