#!/bin/bash

usage() {
	echo ""
	echo "Usage:"
	echo "create-centos-lxc.sh CENTOS_SERIES CONTAINER_NAME STORAGE_SIZE [NEED_CONFIG]"
	echo "create-centos-lxc.sh -c CONTAINER_NAME"
	echo ""
	echo "NEED_CONFIG: yes or no(default)"
	echo "             setup ssh/gpg key and copy/clone tools"
	echo ""
}

config_container() {
	echo "setup ssh auth"
	IDPUB=$(cat ~/.ssh/id_rsa.pub)
	lxc exec "$1" -- /bin/bash -c "mkdir -p /root/.ssh"
	lxc exec "$1" -- /bin/bash -c "echo $IDPUB > /root/.ssh/authorized_keys"
        while true; do
	        lxc exec "$1" -- /bin/bash -c "dhclient eth0"
                if [ "$?" = "0" ]; then
                        break
                else
                        sleep 5
                fi
        done
	lxc exec "$1" -- /bin/bash -c "yum update"
	lxc exec "$1" -- /bin/bash -c "yum install wget git openssh-server bash-completion tar libffi-devel -y"
        if [ "$CENTOS_SERIES" = "centos7" ]; then
	        lxc exec "$1" -- /bin/bash -c "yum install epel-release dnf python-virtualenv centos-release-scl -y"
	        lxc exec "$1" -- /bin/bash -c "yum-config-manager --enable rhel-server-rhscl-7-rpms"
	        lxc exec "$1" -- /bin/bash -c "yum install devtoolset-8 -y"
	        lxc exec "$1" -- /bin/bash -c "echo 'scl enable devtoolset-8 bash' > /root/enalbe-devtoolset-8"
        else
	        lxc exec "$1" -- /bin/bash -c "yum install python3-virtualenv -y"
	        lxc exec "$1" -- /bin/bash -c 'yum groupinstall "Development Tools" -y'
        fi
	lxc exec "$1" -- /bin/bash -c "systemctl start sshd"
	echo "done"
	
	echo "waiting for user to be created"
	while true; do
                running=$(lxc exec "$1" -- /bin/bash -c "systemctl status sshd | grep active | grep running")
		if [ -z "$running" ]; then
			sleep 1
		else
                        break
		fi
	done
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
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa root@"$ADDR":~/.ssh/
	scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.ssh/id_rsa.pub root@"$ADDR":~/.ssh/
	scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.gnupg root@"$ADDR":~/
	scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ~/.gitconfig root@"$ADDR":~/
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$ADDR" git clone https://github.com/gerald-yang/ceph-tools
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

CENTOS_SERIES="$1"
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
lxc launch "$CENTOS_SERIES" "$CONTAINER_NAME" --storage="$CONTAINER_NAME"-disk
if [ "$?" != "0" ]; then
	echo "launch $CONTAINER_NAME failed"
	exit 1
fi
echo "done"

if [ "$NEED_CONFIG" = "yes" ]; then
	config_container "$CONTAINER_NAME"
fi
