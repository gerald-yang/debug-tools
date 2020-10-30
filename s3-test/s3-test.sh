#!/bin/bash

./s3-create-user.sh

NUM_TB=10

dd if=/dev/urandom of=tempobj bs=128K count=3

for ((i=0; i<NUM_TB; i++)); do
	echo "create testbucket$i"
	s3cmd mb s3://testbucket"$i"
	s3cmd put tempobj s3://testbucket"$i"/obj"$i"
done
