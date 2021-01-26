#! /usr/bin/python3

import sys
import math
import pandas as pd
import argparse
import itertools

from bokeh.plotting import figure, output_file, show
from bokeh.palettes import Dark2_5 as palette

examples = """examples:
    ./estimate.py                        # summarize block I/O latency as a histogram
    ./esitmate.py 1                      # print 1 second summaries
    ./estimate.py -m 1                   # 1s summaries, milliseconds
    ./estimate.py -m 1 --rootdisk sda    # 1s summaries, milliseconds, exclude sda
"""
parser = argparse.ArgumentParser(
    description="Plot a disk latency history by bokeh",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=examples)
parser.add_argument("-i", "--inputfile", default="latency.log",
    help="result from estimate.py")
parser.add_argument("-o", "--outputfile", default="latency.html",
    help="output html file")
parser.add_argument("-t", "--threshold", default=16,
    help="threshold for high disk latency")
args = parser.parse_args()

#colors has a list of colors which can be used in plots 
colors = itertools.cycle(palette) 

# prepare timeline
x = []
y_dict = {}

# create disk list
with open(args.inputfile, "r") as f:
    while True:
        line = f.readline()
        if line == '':
            break
        if line.find('disk') != -1:
            disk_name = line.rstrip('\n').split('=')[1].strip()
            if disk_name not in y_dict:
                y = []
                y_dict[disk_name] = y

time_iter = 0
with open(args.inputfile, "r") as f:
    while True:
        line = f.readline()
        if line == '':
            break
        if line.find('2021-') != -1:
            if time_iter > 0:
                for disk in y_dict:
                    if len(y_dict[disk]) != time_iter:
                        #print(time_iter)
                        #print('missing: ' + disk)
                        y_dict[disk].append(0)
            x.append(line)
            time_iter += 1
        if line.find('disk') != -1:
            #print(line)
            disk_name = line.rstrip('\n').split('=')[1].strip()
            #print(disk_name)
            # filter 'log : msecs : counts'
            f.readline()
            high = 0
            while True:
                line_log = f.readline()
                if line_log == '' or line_log == '\n':
                    break
                log = int(line_log.split(':')[0].strip(), 10)
                count = int(line_log.split(':')[2].rstrip('\n').strip(), 10)
                if math.pow(2, log) > int(args.threshold):
                    high += count

            y_dict[disk_name].append(high)
                    
for disk in y_dict:
    if len(y_dict[disk]) != time_iter:
        y_dict[disk].append(0)
# output to static HTML file
output_file(args.outputfile)

# create a new plot with a title and axis labels
p = figure(title="High disk latency history", plot_width=1400, plot_height=800, x_axis_label="timeline", x_axis_type="datetime", y_axis_label="Number of IOs that disk latency higher than " + args.threshold + " milliseconds")

x = pd.to_datetime(x)
for disk in y_dict:
    p.line(x, y_dict[disk], color=next(colors), legend_label=disk, line_width=2)

# show the results
show(p)
