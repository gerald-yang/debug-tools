#!/bin/bash

usage() {
	echo ""
	echo "Usage:"
	echo "delete-lxc.sh CONTAINER_NAME"
	echo ""
}

if [ -z "$1" ]; then
	echo "Wrong parameter 1"
	usage
	exit 1
fi

CONTAINER_NAME="$1"

echo "stopping container $CONTAINER_NAME"
lxc stop "$CONTAINER_NAME"
if [ "$?" != "0" ]; then
	echo "stop $CONTAINER_NAME failed"
	exit 1
fi
echo "done"

echo "deleting container $CONTAINER_NAME"
lxc delete "$CONTAINER_NAME"
if [ "$?" != "0" ]; then
	echo "delete $CONTAINER_NAME failed"
	exit 1
fi
echo "done"

echo "deleting storage $CONTAINER_NAME-disk"
lxc storage delete "$CONTAINER_NAME"-disk
if [ "$?" != "0" ]; then
	echo "delete storage failed"
	exit 1
fi
echo "done"
