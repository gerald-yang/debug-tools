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
    ./plot-memory-states.py -f proc-file.txt -c config -o proc-html
"""
parser = argparse.ArgumentParser(
    description="Plot a chart by bokeh",
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog=examples)
parser.add_argument("-f", "--file", default="proc-file.txt",
    help="perf dump file")
parser.add_argument("-c", "--config", default="config",
    help="configuration file")
parser.add_argument("-o", "--outputd", default="proc-html",
    help="output folder")
args = parser.parse_args()

#colors has a list of colors which can be used in plots
colors = itertools.cycle(palette)

# list of line color
#line_color = ["red", "green", "blue", "black", "yellow", "purple", "brown"]

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


def plot_counters(cfname, counter_list):
    x_timeline = []
    y_dict = {}
    counters = {}
    output_file(args.outputd + '/' + cfname + '.html')

    with open(args.file, "r") as f:
        while True:
            line = f.readline()
            if line == '':
                break
            if line.find('cat /proc/' + cfname) != -1:
                t = line.split()[0] + '.' + line.split()[1].split('.')[0]
                #print(t)
                x_timeline.append(t)
                while True:
                    line = f.readline()
                    if line == '\n':
                        continue
                    if line.find('============================') != -1:
                        break
                    if line.find('%%%%%%%%%%%%%%%%%%%%%%%%%%%%') != -1:
                        break
                    if cfname == 'meminfo':
                        name = line.split(':')[0]
                        value = int(line.split(':')[1].split()[0].rstrip().lstrip())
                    if cfname == 'vmstat':
                        name = line.split()[0]
                        value = int(line.split()[1].rstrip().lstrip())

                    if name in counter_list:
                        if name not in y_dict:
                            y = []
                            y_dict[name] = y
                            y_dict[name].append(0)
                            counters[name] = value
                        else:
                            y_dict[name].append(value - counters[name])
                            counters[name] = value

    # create a new plot with a title and axis labels
    p = figure(title="perf counter diff", plot_width=1800, plot_height=2400, x_axis_label="timeline", x_axis_type="datetime", y_axis_label="counter increased")

    x = pd.to_datetime(x_timeline, format='%Y-%m-%d.%H:%M:%S')
    for c in y_dict:
        p.line(x, y_dict[c], color=next(colors), line_width=2, legend = c)

    p.legend.location = "top_left"
    p.legend.click_policy = "hide"
    # show the results
    show(p)


def get_counter_config(counter_config):
    with open(args.config, "r") as cf:
        while True:
            line = cf.readline()
            if line == '':
                break
            if line.find('{') != -1:
                cfname = cf.readline().rstrip('\n')
                name = []
                while True:
                    line = cf.readline()
                    if line.find('}') != -1:
                        break
                    if line[0] != '#':
                        name.append(line.rstrip('\n'))
                counter_config[cfname] = name


def create_counter_list(fname):
    print(fname)
    with open(args.file, "r") as f:
        while True:
            line = f.readline()
            if line == '':
                break
            if line.find('cat /proc/' + fname) != -1:
                while True:
                    line = f.readline()
                    if line.find('%%%%%%%%%%%%%%%%%%%%%%%%') != -1:
                        #print('end')
                        exit(0)
                    if line != '\n':
                        #print(line)
                        name = line.split()[0]
                        value = line.split()[1].rstrip().lstrip()
                        print(name)
                        #print(value)


#proc_files = ['meminfo', 'buddyinfo', 'zoneinfo', 'vmstat']
#create_counter_list(pf[0])

with open(args.config, "r") as cf:
    counter_config = {}
    get_counter_config(counter_config)
    #print(counter_config)

    for cfname in counter_config:
        print('plotting ' + cfname)
        plot_counters(cfname, counter_config[cfname])

