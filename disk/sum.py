#! /usr/bin/python3

import sys
import math

estimate_sum = {}

if len(sys.argv) != 2:
    print('enter log file')
    sys.exit(1)

with open(sys.argv[1], "r") as f:
    while True:
        line = f.readline()
        if line == '':
            break
        if line.find('disk') != -1:
            #print(line)
            disk_name = line.rstrip('\n').split('=')[1].strip()
            #print(disk_name)
            # create a dictionary for log/latency
            if disk_name not in estimate_sum:
                new_dict = {}
                estimate_sum[disk_name] = new_dict
            # filter 'log : msecs : counts'
            f.readline()
            while True:
                line_log = f.readline()
                if line_log == '' or line_log == '\n':
                    break
                log = int(line_log.split(':')[0].strip(), 10)
                count = int(line_log.split(':')[2].rstrip('\n').strip(), 10)
                if log not in estimate_sum[disk_name]:
                    estimate_sum[disk_name][log] = count
                else:
                    estimate_sum[disk_name][log] += count

#print(estimate_sum)

for disk in estimate_sum:
    log_len = len(estimate_sum[disk])
    total_io = 0
    print(disk)
    for i in range(log_len):
        if i == 0:
            low = 0
        else:
            low = math.pow(2, i-1)
        high = math.pow(2, i)
        print("%d : %d -> %d : %d" % (i, low, high, estimate_sum[disk][i]))
        total_io += estimate_sum[disk][i]
    print("total IO: %d" % total_io)
    print('')
