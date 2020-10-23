#!/bin/bash

FPATH="flamegraph/"
DROP_PERF_DATA=false
OUTPUT_FOLDER="per-cpu-flamegraph"
PERF_SCRIPT_CMD="perf script"
PERF_REPORT="perf-temp"
GREP_STRINGS=""
KERNEL_VERSION=""
MAXCPUNR=0
PER_CPU_FLAMEGRAPH=false
SUBTITLE=""
SYMFS=""
TAR=false
TITLE=""

# $1:$PSCRIPT $2:$TITLE $3:$SUBTITLE $4:$PSVG $5:$PFOLDED
__generate_flamegraph() {

	# extract the call stack for the flamegraph.pl to generate the svg interactive graph
	"${FPATH}"stackcollapse-perf.pl --all "$1" > "$5"

	if [[ $GREP_STRINGS == "" ]]; then
	    #cat ${PFOLDED} | ${FPATH}flamegraph.pl > ${PSVG}
	    grep -Pv 'addr2line|stackcollapse' "$5" | "${FPATH}"flamegraph.pl --color java --title "$2" --subtitle "$3" > "$4"
	else
	    # add the string name to the SVG name to identify the file easily
	    PSVG="$5S$GREP_STRINGS.svg"
	    grep -E "$GREP_STRINGS" "$5" | "${FPATH}"flamegraph.pl --color java --title "$2" --subtitle "$3" > "$4"
	fi
}

generate_per_cpu_flamegraph() {

	local CURRENT_LINE_NR=1
	local PREV_LINE_NR=1
	local CURRENT_CPU_NR=0
	local PREV_CPU_NR=0
	local FILE="$1"
	local PCPUSCRIPT
	local PCPUFOLDED
	local PCPUSVG
	# Associative array is local when it's declared inside the function
	declare -A cpu_array

	# $ grep -Pn '.+\s+\d+\s+\[\d+\] \d+\.\d+:\s+\d+\scycles:\s+' /var/log/easy-flamegraph/cpu/2020-02-11_220302.perf.cpu.t0.u12.1.script
	# 1:swapper     0 [000] 375287.542317:          1 cycles:
	# 26:swapper     0 [000] 375287.542324:          1 cycles:
	# 51:swapper     0 [000] 375287.542327:        178 cycles:

	while read -r i; do

		# Parse the current line number
		CURRENT_LINE_NR=$(echo "$i" |grep -Po '^\d+')

		if [ "$CURRENT_LINE_NR" = "" ]; then
			continue
		fi

		# echo LINE:$CURRENT_LINE_NR

		if [ "$CURRENT_LINE_NR" -ne "$PREV_LINE_NR" ]; then
			((CURRENT_LINE_NR = CURRENT_LINE_NR - 1))
			PCPUSCRIPT="${OUTPUT_FOLDER}/$(basename "$PERF_REPORT").cpu${PREV_CPU_NR}.script"

			# Remove the previous script to avoid reuse the previous data
			if [ "${cpu_array[$PREV_CPU_NR]}"x == ""x ]; then
				# echo PREV_CPU_NR:$PREV_CPU_NR in if
				# echo cpu_array[PREV_CPU_NR]:${cpu_array[PREV_CPU_NR]} in if
				[ -e "$PCPUSCRIPT" ] && rm "$PCPUSCRIPT" && echo remove the existing "$PCPUSCRIPT"!
			fi

			#echo PREV_CPU_NR:$PREV_CPU_NR in else
			#echo cpu_array[PREV_CPU_NR]:$PREV_CPU_NR in else
			cpu_array[$PREV_CPU_NR]=$((${cpu_array[$PREV_CPU_NR]}+1))

			sed -n "$PREV_LINE_NR,${CURRENT_LINE_NR}p" "$FILE" >> "$PCPUSCRIPT"
			# echo "$PREV_LINE_NR,${CURRENT_LINE_NR}p $FILE >> ${PCPUSCRIPT}"
		fi

		PREV_LINE_NR=$CURRENT_LINE_NR

		# Parse the CPU number of the callstack
		PREV_CPU_NR=$(echo "$i" | perl -n -e '/\[(\d+)\]/; print $1')
		# echo CPU_NR:$PREV_CPU_NR

		if [ "$PREV_CPU_NR" -ge "$MAXCPUNR" ]; then
			MAXCPUNR="$PREV_CPU_NR"
		fi

	done <<< "$(grep -Pn '.+\s+\d+\s+\[\d+\] ' "$FILE")"

	# This is the case to handle the last callstack and try to get the last line
	CURRENT_LINE_NR=$(wc -l < "$FILE")

	# echo $CURRENT_LINE_NR
	# Check the empty file condition that the while loop is skipped
	if [ "$PREV_LINE_NR" -lt "$CURRENT_LINE_NR" ] ; then
		PCPUSCRIPT="${OUTPUT_FOLDER}/$(basename "$PERF_REPORT").cpu${PREV_CPU_NR}.script"

			# Remove the previous script to avoid reuse the previous data
			if [ "${cpu_array[$PREV_CPU_NR]}"x == ""x ]; then
				[ -e "$PCPUSCRIPT" ] && rm "$PCPUSCRIPT" && echo remove the existing "$PCPUSCRIPT"!
			fi

			cpu_array[$PREV_CPU_NR]=$((${cpu_array[$PREV_CPU_NR]}+1))

			sed -n "$PREV_LINE_NR,${CURRENT_LINE_NR}p" "$FILE" >> "$PCPUSCRIPT"
			# echo "$PREV_LINE_NR,${CURRENT_LINE_NR}p $FILE >> ${1}.cpu${PREV_CPU_NR}"
	fi

	# Remove leading 0
	MAXCPUNR=${MAXCPUNR#0}

	# Finally, generate the flamegraph
	for ((i = 0; i <= MAXCPUNR; i++)); do
		PCPUSCRIPT="${OUTPUT_FOLDER}/$(basename "$PERF_REPORT")$(printf .cpu%03d "$i").script"
		PCPUFOLDED="${OUTPUT_FOLDER}/$(basename "$PERF_REPORT")$(printf .cpu%03d "$i").folded"
		PCPUSVG="${OUTPUT_FOLDER}/$(basename "$PERF_REPORT")$(printf .cpu%03d "$i").svg"

		__generate_flamegraph "$PCPUSCRIPT" "per cpu" "cpu $i" "${PCPUSVG}" "${PCPUFOLDED}"
	done

	# Use the following instructions to verify the correctness
	# $ grep -Pn '.+\s+\d+\s+\[\d+\] \d+\.\d+:\s+\d+\scycles:\s+' perf-output/perf.datacpu00*script | wc -l
	# 3968
	# $ grep -Pn '.+\s+\d+\s+\[\d+\] \d+\.\d+:\s+\d+\scycles:\s+' perf-output/perf.data.script | wc -l
	# 3968

}

clean_exit() {
	# nothing to do
	echo
}


# mkdir the folder to store the perf report data
mkdir -p "$OUTPUT_FOLDER"

# generate the perf script file for the stackcollapse to extract the call stack
#${PERF_SCRIPT_CMD} > "$PSCRIPT"

generate_per_cpu_flamegraph "$1"
