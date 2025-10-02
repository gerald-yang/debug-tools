#ifndef NFNETLINK_RCV_BATCH_COMMON_H
#define NFNETLINK_RCV_BATCH_COMMON_H

#ifndef __u32
typedef unsigned int __u32;
#endif

struct event {
    __u32 len;
};

#endif
