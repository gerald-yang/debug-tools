#! /usr/bin/python3

import os
import sys
import math
import pandas as pd
import argparse
import itertools

from bokeh.plotting import figure, output_file, show
from bokeh.palettes import Dark2_5 as palette

examples = """examples:
    ./bokeh.py -d data
"""
parser = argparse.ArgumentParser(
    description="Plot a history by bokeh",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=examples)
parser.add_argument("-d", "--directory", default="data",
    help="folder contain network data")
parser.add_argument("-o", "--output", default="net.html",
    help="output html file")
args = parser.parse_args()

#colors has a list of colors which can be used in plots
colors = itertools.cycle(palette)

# prepare timeline
x_timeline = []
y_dict = {}

# counter name
'''
counters = {'segments retransmitted':0, 'active connection openings':0, 'failed connection attempts':0,
        'resets sent':0, 'packets to unknown port received':0, 'resets received for embryonic SYN_RECV sockets':0,
        'fast retransmits':0, 'retransmits in slow start':0, 'connections reset due to unexpected data':0,
        'TCPSackRecovery:':0, 'TCPLostRetransmit:':0, 'TCPSackFailures:':0, 'TCPTimeouts:':0, 'TCPLossProbes:':0,
        'TCPLossProbeRecovery:':0, 'TCPSackRecoveryFail:':0, 'TCPBacklogCoalesce:':0, 'TCPRcvCoalesce:':0}
'''

counters = {'segments retransmitted':0,
        'fast retransmits':0, 'retransmits in slow start':0,
        'TCPLostRetransmit:':0, 'TCPTimeouts:':0}

packet_drop = {}
#packet_drop = {' enp6s0f0:':0, ' enp6s0f1:':0}

# list of line color
line_color = ["red", "green", "blue", "black", "yellow", "purple", "brown"]
'''
line_color = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF",
        "#FFFFFF", "#F0F0F0", "#0F0F0F", "#F00000", "#0F0000", "#00F000",
        "#000F00", "#0000F0", "#00000F", "#FFF000", "#000FFF", "#F00FFF", "#FFF00F"]
'''


if not os.path.isdir(args.directory):
    print("error: " + args.directory + " is not a directory")
    exit(1)

for folder in os.listdir(args.directory):
    if os.path.isdir(args.directory + "/" + folder):
        #print('folder: ' + folder)
        x_timeline.append(folder)

x_timeline = sorted(x_timeline)

for data_folder in x_timeline:
    #print("open " + data_folder)
    with open(args.directory + "/" + data_folder + "/netstat_-s", "r") as f:
        while True:
            line = f.readline()
            if line == '':
                break
            for counter, base in counters.items():
                if line.find(counter) != -1:
                    if base == 0:
                        if line.find('TCP') != -1:
                            counters[counter] = int(line.split()[1])
                        else:
                            counters[counter] = int(line.split()[0])
                        #print(counter + " base: " + str(counters[counter]))
                        y = []
                        y_dict[counter] = y
                        y_dict[counter].append(0)
                    else:
                        if line.find('TCP') != -1:
                            tmp = int(line.split()[1])
                        else:
                            tmp = int(line.split()[0])
                        y_dict[counter].append(tmp - counters[counter])
                        counters[counter] = tmp
                        #print(counter + " increase: " + str(y_dict[counter]))

    with open(args.directory + "/" + data_folder + "/ip_-s_-s_-d_link_show", "r") as f:
        while True:
            line = f.readline()
            if line == '':
                break
            for drop, base in packet_drop.items():
                if line.find(drop) != -1:
                    line = f.readline()
                    line = f.readline()
                    line = f.readline()
                    rx_drop = int(line.split()[3])
                    if base == 0:
                        packet_drop[drop] = rx_drop
                        y = []
                        y_dict[drop] = y
                        y_dict[drop].append(0)
                    else:
                        y_dict[drop].append(rx_drop - packet_drop[drop])
                        packet_drop[drop] = rx_drop


# output to static HTML file
output_file(args.output)

# create a new plot with a title and axis labels
p = figure(title="network counter diff", plot_width=1400, plot_height=800, x_axis_label="timeline", x_axis_type="datetime", y_axis_label="counter increased")

x = pd.to_datetime(x_timeline, format='%Y.%m.%d-%H.%M.%S')
line_color_iter = 0
for c in y_dict:
    p.line(x, y_dict[c], color=line_color[line_color_iter], legend_label=c, line_width=2)
    line_color_iter = line_color_iter + 1

# show the results
show(p)
