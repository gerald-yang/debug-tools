#!/bin/bash

ceph daemon osd.0 config set osd_op_complaint_time 0.05
TESTPOOL=$(rados lspools | grep testp)
if [ -z "$TESTPOOL" ]; then
        ceph osd pool create testp 64 64
        ceph osd pool application enable testp rbd
fi

rados bench 10 write --no-cleanup -p testp
