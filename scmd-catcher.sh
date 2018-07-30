#!/bin/bash

while true;
do
	date
	echo "check scmd error"
	scmd_err=$(dmesg | grep 'task abort called for scmd')
	if ! [ -z "$scmd_err" ]; then
		echo "scmd error"
		/opt/MegaRAID/storcli/storcli64 show all logfile=all.log
		/opt/MegaRAID/storcli/storcli64 /c0 show events logfile=events.log
		/opt/MegaRAID/storcli/storcli64 /c0 show eventloginfo logfile=eventloginfo.log
		/opt/MegaRAID/storcli/storcli64 /c0 show termlog logfile=termlog.log
		break
	fi

	sleep 30
done

