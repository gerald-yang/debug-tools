import numpy as np
import pandas as pd

from bokeh.io import show
from bokeh.layouts import column
from bokeh.models import ColumnDataSource, RangeTool, HoverTool
from bokeh.plotting import figure
from bokeh.sampledata.stocks import AAPL

scan = pd.read_csv("/home/vin/os/easy-flamegraph/profile/cleansing/test_csv/pgscan_kswapd.csv")
scan['date'] = pd.to_datetime(scan['date'])
scan['value'] = pd.to_numeric(scan['value'])
scan['value'] = pd.Series(scan['value'])
scan = scan.query("date >= '2020-11-04-05:22:25' \
                       and date < '2020-11-10'")
dates = np.array(scan['date'], dtype=np.datetime64)
source = ColumnDataSource(data=dict(date=dates, close=scan['value'].diff()))
#dates = np.array(AAPL['date'], dtype=np.datetime64)
#source = ColumnDataSource(data=dict(date=dates, close=AAPL['adj_close']))
pageoutrun = pd.read_csv("/home/vin/os/easy-flamegraph/profile/cleansing/test_csv/pageoutrun.csv")
pageoutrun['date'] = pd.to_datetime(pageoutrun['date'])
pageoutrun['value'] = pd.to_numeric(pageoutrun['value'])
source1 = ColumnDataSource(data=dict(date=dates, close=pageoutrun['value']))

p = figure(plot_height=300, plot_width=800, tools="xpan", toolbar_location=None,
           x_axis_type="datetime", x_axis_location="above",
           background_fill_color="#efefef", x_range=(dates[1500], dates[2500]))

p.line('date', 'close', source=source, legend="pgscan_kswapd")
p.line('date', 'close', source=source1, legend="pageoutrun")
p.yaxis.axis_label = 'Count'

select = figure(title="Drag the middle and edges of the selection box to change the range above",
                plot_height=130, plot_width=800, y_range=p.y_range,
                x_axis_type="datetime", y_axis_type=None,
                tools="", toolbar_location=None, background_fill_color="#efefef")

range_tool = RangeTool(x_range=p.x_range)
range_tool.overlay.fill_color = "navy"
range_tool.overlay.fill_alpha = 0.2

p.legend.click_policy="hide"
p.add_tools(HoverTool(
    tooltips=[
        ("(date, close)", "(@date{%F-%T}, @close)"),
    ],
    formatters={'@date': 'datetime'},
    mode='vline'
))

select.line('date', 'close', source=source)
select.line('date', 'close', source=source1)
select.ygrid.grid_line_color = None
select.add_tools(range_tool)
select.toolbar.active_multi = range_tool

show(column(p, select))
