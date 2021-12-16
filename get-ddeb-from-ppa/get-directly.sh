#!/bin/bash

UCA="ussuri"

grep 'amd64' list | grep 'dbgsym' | awk '{print $1}'> amd64

while read pkg; do
	echo "download $pkg"
	wget https://launchpad.net/~ubuntu-cloud-archive/+archive/ubuntu/"$UCA"-updates-ddeb/+files/$pkg
done <amd64
