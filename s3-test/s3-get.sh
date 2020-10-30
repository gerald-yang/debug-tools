#!/bin/bash

NUM_TB=10

for ((i=0; i<NUM_TB; i++)); do
	echo "get obj$i"
	s3cmd get s3://testbucket"$i"/obj"$i" obj"$i"
done
