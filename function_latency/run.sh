#!/bin/bash

while IFS='' read -r line || [[ -n "$line" ]]; do
    echo "Start tracing function: $line"
    trace-cmd -p function_graph -l "$line" ./fio1.sh /dev/escache0
done < "function_list"


