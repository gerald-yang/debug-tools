#!/bin/bash

START1="4"
END1="39"
START2="44"
END2="79"
START3="80"
END3="119"
START4="120"
END4="159"

ISOA1="cpu >= $START1 && cpu <= $END1"
ISOA2="cpu >= $START2 && cpu <= $END2"
ISOA3="cpu >= $START3 && cpu <= $END3"
ISOA4="cpu >= $START4 && cpu <= $END4"

ISOB1="dst_cpu >= $START1 && dst_cpu <= $END1"
ISOB2="dst_cpu >= $START2 && dst_cpu <= $END2"
ISOB3="dst_cpu >= $START3 && dst_cpu <= $END3"
ISOB4="dst_cpu >= $START4 && dst_cpu <= $END4"

ISOC1="dest_cpu >= $START1 && dest_cpu <= $END1"
ISOC2="dest_cpu >= $START2 && dest_cpu <= $END2"
ISOC3="dest_cpu >= $START3 && dest_cpu <= $END3"
ISOC4="dest_cpu >= $START4 && dest_cpu <= $END4"

ISOD1="target_cpu >= $START1 && target_cpu <= $END1"
ISOD2="target_cpu >= $START2 && target_cpu <= $END2"
ISOD3="target_cpu >= $START3 && target_cpu <= $END3"
ISOD4="target_cpu >= $START4 && target_cpu <= $END4"

trace-cmd record -e sched:sched_wake_idle_without_ipi -f "$ISOA1" -f "$ISOA2" -f "$ISOA3" -f "$ISOA4" -e sched:sched_swap_numa -f "$ISOB1" -f "$ISOB2" -f "$ISOB3" -f "$ISOB4" -e sched:sched_stick_numa -f "$ISOB1" -f "$ISOB2" -f "$ISOB3" -f "$ISOB4" -e sched:sched_move_numa -f "$ISOB1" -f "$ISOB2" -f "$ISOB3" -f "$ISOB4" -e sched:sched_migrate_task -f "$ISOC1" -f "$ISOC2" -f "$ISOC3" -f "$ISOC4" -e sched:sched_wakeup_new -f "$ISOD1" -f "$ISOD2" -f "$ISOD3" -f "$ISOD4" -e sched:sched_wakeup -f "$ISOD1" -f "$ISOD2" -f "$ISOD3" -f "$ISOD4" -e sched:sched_waking -f "$ISOD1" -f "$ISOD2" -f "$ISOD3" -f "$ISOD4" 
