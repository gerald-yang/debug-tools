#!/bin/bash

usage() {
	echo ""
	echo "Usage:"
	echo "create-lxc.sh {ubuntu series} {container name} {storage size} {create storage} {from daily}"
	echo ""
	echo "Configure container only"
	echo "create-lxc.sh -c {container name}"
	echo ""
        echo ""
        echo "Example:"
        echo "./create-lxc.sh noble noble-c 30 yes no"
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
	#ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/gerald-yang/debug-tools
	#ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$ADDR" git clone https://github.com/brendangregg/flamegraph

	echo "" >> ~/.ssh/config
	echo "Host $1" >> ~/.ssh/config
	echo "  ForwardAgent yes" >> ~/.ssh/config
	echo "  HostName $ADDR" >> ~/.ssh/config
	echo "  User ubuntu" >> ~/.ssh/config
}

SERIES="$1"
NAME="$2"
DISK="$3"
CREATE_DISK="$4"
FROM_DAILY="$5"

if [ "$SERIES" = "-c" ]; then
        if [ -z "$NAME" ]; then
                echo "enter container name to be configured"
                exit -1
        fi
        config_container "$NAME"
        exit 0
fi

if [ -z "$5" ]; then
	echo "Wrong parameters"
	usage
	exit 1
fi

if [ "$CREATE_DISK" = "yes" ]; then
        echo "creating storage $NAME-disk"
        lxc storage create "$NAME"-disk zfs size="$DISK"GB
        if [ "$?" != "0" ]; then
	        echo "create storage failed"
	        exit 1
        fi
        echo "done"
fi

echo "launching container $NAME"
if [ "$CREATE_DISK" = "yes" ]; then
	if [ "$FROM_DAILY" == "yes" ]; then
        	lxc launch ubuntu-daily:"$SERIES" "$NAME" --storage="$NAME"-disk
	else
        	lxc launch ubuntu:"$SERIES" "$NAME" --storage="$NAME"-disk
	fi
else
	if [ "$FROM_DAILY" == "yes" ]; then
        	lxc launch ubuntu-daily:"$SERIES" "$NAME"
	else
        	lxc launch ubuntu:"$SERIES" "$NAME"
	fi
fi

if [ "$?" != "0" ]; then
	echo "launch $NAME failed"
	exit 1
fi
echo "done"

config_container "$NAME"
