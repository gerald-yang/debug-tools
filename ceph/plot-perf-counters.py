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
    ./bokeh.py -f perf-dump.txt -o perf-dump.html
"""
parser = argparse.ArgumentParser(
    description="Plot a history by bokeh",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=examples)
parser.add_argument("-f", "--file", default="perf-dump.txt",
    help="perf dump file")
parser.add_argument("-c", "--config", default="config",
    help="configuration file")
parser.add_argument("-o", "--outputd", default="osd.xxxx",
    help="output folder")
args = parser.parse_args()

#colors has a list of colors which can be used in plots
colors = itertools.cycle(palette)

# prepare timeline
x_timeline = []
y_dict = {}
counters = {}
counter_list = []

# list of line color
#line_color = ["red", "green", "blue", "black", "yellow", "purple", "brown"]
line_color = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF",
        "#FFFFFF", "#F0F0F0", "#0F0F0F", "#F00000", "#0F0000", "#00F000",
        "#000F00", "#0000F0", "#00000F", "#FFF000", "#000FFF", "#F00FFF", "#FFF00F",
        "#FFFFF0", "#0FFFFF", "#F0FFFF", "#FF0FFF", "#FFF0FF", "#FFFF0F",
        "#00FFFF", "#FFFF00", "#F0F000", "#F00F00", "#F000F0", "#F0000F",
        "#0F0F00", "#0F00F0", "#0F000F", "#00F0F0", "#00F00F", "#000F0F",
        "#F00FF0", "#F000FF", "#FF0F00", "#FF00F0", "#FF000F", "#F0F00F",
        "#AAAAAA", "#A0A0A0", "#0A0A0A", "#A00000", "#0A0000", "#00A000",
        "#000A00", "#0000A0", "#00000A", "#AAA000", "#000AAA", "#A00AAA",
        "#00AAAA", "#0A00A0", "#0A000A", "#00A0A0", "#00A00A", "#000A0A",
        "#A00AA0", "#A000AA", "#AA0A00", "#AA00A0", "#AA000A", "#A0A00A",
        "#555555", "#505050", "#050505", "#500000", "#050000", "#005000",
        "#000500", "#000050", "#050505", "#500000", "#550055", "#505050",
        "#005555", "#050050", "#050005", "#550050", "#550005", "#505005",
        "#666666", "#606060", "#060606", "#600000", "#060000", "#006000",
        "#000600", "#000060", "#000006", "#660000", "#006600", "%000066"]

if not os.path.isfile(args.file):
    print("error: " + args.file + " is not a file")
    exit(1)


if not os.path.isfile(args.config):
    print("error: " + args.config + " is not a file")
    exit(1)


try:
    os.mkdir(args.outputd)
except OSError:
    print("Creation of the directory %s failed" % args.outputd)
else:
    print("Successfully created the directory %s " % args.outputd)

#tmp = 0

def get_counters_in_category(f):
    #global tmp
    while True:
        line = f.readline()
        name = line.split(':')[0].strip().strip('"')
        if line.find('{') != -1:
            while True:
                line = f.readline()
                if line.find('avgcount') != -1:
                    value = int(line.split(':')[1].strip().strip(','))
                elif line.find('}') != -1:
                    break
                else:
                    continue
        elif line.find('}') != -1:
            break
        else:
            value = float(line.split(':')[1].strip().strip(','))

        #if tmp == 1:
        #    print(name)
        if line[0] != '#' and name in counter_list:
            if name not in y_dict:
                y = []
                y_dict[name] = y
                y_dict[name].append(0)
                counters[name] = value;
            else:
                y_dict[name].append(value - counters[name])
                counters[name] = value;


def plot_counters(cname):
    #global tmp
    output_file(args.outputd + '/' + cname.replace(':', '-') + '.html')

    with open(args.file, "r") as f:
        while True:
            line = f.readline()
            if line == '':
                break
            if line.find('perf_dump OSD') != -1:
                t = line.split()[0] + '.' + line.split()[1].split('.')[0]

                x_timeline.append(t)
                while True:
                    line = f.readline()
                    if line.find('"'+cname+'"') != -1:
                        #if tmp == 1:
                        #    print('{')
                        #    print(cname)
                        get_counters_in_category(f)
                        #if tmp == 1:
                        #    print('}')
                    elif line.find('====================================================') != -1:
                        #tmp = 0
                        break
                    else:
                        continue

    # create a new plot with a title and axis labels
    p = figure(title="perf counter diff", plot_width=1800, plot_height=2400, x_axis_label="timeline", x_axis_type="datetime", y_axis_label="counter increased")

    x = pd.to_datetime(x_timeline, format='%Y-%m-%d.%H:%M:%S')
    line_color_iter = 0
    for c in y_dict:
        p.line(x, y_dict[c], color=next(colors), legend_label=c, line_width=2)
        line_color_iter = line_color_iter + 1

    # show the results
    show(p)

with open(args.config, "r") as cf:
    counter_list = []
    while True:
        line = cf.readline()
        if line == '':
            break
        if line.find('{') != -1:
            cname = cf.readline().rstrip("\n")
            while True:
                line = cf.readline()
                if line.find('}') != -1:
                    break
                counter_list.append(line.rstrip("\n"))
            
            #tmp = 1
            print('plotting ' + cname + ' counters')
            plot_counters(cname)
        
        counter_list.clear()
        y_dict.clear()
        x_timeline.clear()
        counters.clear()


