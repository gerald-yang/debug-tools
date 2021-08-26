#!/bin/bash

if [ "$1" = "crimson" ]; then
	../src/stop.sh --crimson
else
	../src/stop.sh
fi
