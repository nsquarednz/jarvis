/**
 * Description: This code generates the various types of graphs used by 
 *              the Jarvis Tracker system. These graphs are designed to
 *              be shown via the Visualisation Ext component.
 *
 * Licence:
 *       This file is part of the Jarvis Tracker application.
 *
 *       Jarvis is free software: you can redistribute it and/or modify
 *       it under the terms of the GNU General Public License as published by
 *       the Free Software Foundation, either version 3 of the License, or
 *       (at your option) any later version.
 *
 *       Jarvis is distributed in the hope that it will be useful,
 *       but WITHOUT ANY WARRANTY; without even the implied warranty of
 *       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *       GNU General Public License for more details.
 *
 *       You should have received a copy of the GNU General Public License
 *       along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
 *
 *       This software is Copyright 2008 by Jamie Love.
 */

Ext.ns('jarvis.graph');

/******************************************************************************
 * Base graph class.
 *****************************************************************************/
jarvis.graph.Graph = function(config) {
    Ext.apply (this, config);

    this.addEvents(
        /**
         * An event fired before the loading of datasets is started.
         */
        'click'
    );

    jarvis.graph.Graph.superclass.constructor.call(this); // Observer constructor call.
};

Ext.extend (jarvis.graph.Graph, Ext.util.Observable, {

    /*
     * Provide a title for the graph.
     */
    title: function() {
            throw 'ERROR: base graph "title" function called. This is an abstract function and needs to be overridden.';
    },

    /*
     * Rendering function. Renders to 'el' with the given data
     * 
     * Parameters:
     *      el      - is a Ext.Element object. 
     *      data    - is an array of data points, graph specific.
     *      config  - configuration for rendering the graph, graph
     *                specific.
     */
    render: function (el, data, config) {
        throw 'ERROR: base graph "render" function called. This is an abstract function and needs to be overridden.';
    },

    /*
     * Provide a message indicating there is no data to display a graph on the 
     * given element (not the same as if there was an error reading the data!)
     */
    noDataMessage: function(el) {
        el.getEl().update ('<i>No data available to display graph.</i>');
    },

    /*
     * The default colors to use. We assume that the general page is blue, so we choose
     * a good contrasting color (orange in this case).
     */
    defaultColors:  pv.color('#B77A1B')
});

/******************************************************************************
 * Graph showing performance of a dataset query
 *****************************************************************************/
jarvis.graph.DatasetPerformanceGraph = Ext.extend(jarvis.graph.Graph, {
    title: function () {
        return 'Dataset Performance';
    },

    render: function (el, data, config) {

        if (data.length < 4) { // Need a few data points to make this work nicely
            this.noDataMessage (el);
            return;
        }
        
        var elBox = el.getBox();

        leftBuffer = 20;
        rightBuffer = 10;
        bottomBuffer = 20;

        width = elBox.width - 20 - leftBuffer - rightBuffer; // 20 pixels gives a buffer to avoid scrollbars under Chrome TODO - fix
        height = 60 - bottomBuffer;

        // Lets look at the data
        var sortedData = data.sort (function (a, b) { return a.d - b.d });
        var sortedDataLen = sortedData.length;

        var mean = pv.mean (sortedData, function (d) { return d.d; });
        var median = sortedDataLen % 2 == 1 ? sortedData[Math.floor(sortedDataLen / 2)].d : (sortedData[sortedDataLen / 2].d + sortedData[sortedDataLen / 2 - 1].d) / 2;
        var lowerQuartile = Math.floor (sortedDataLen / 2) % 2 == 1 ? sortedData[Math.floor(sortedDataLen / 4)].d : (sortedData[Math.floor(sortedDataLen / 4)].d + sortedData[Math.floor(sortedDataLen / 4) - 1].d) / 2;
        var upperQuartile = Math.floor (sortedDataLen / 2) % 2 == 1 ? sortedData[sortedDataLen - Math.floor(sortedDataLen / 4) - 1].d : (sortedData[sortedDataLen - Math.floor(sortedDataLen / 4) - 1].d + sortedData[sortedDataLen - Math.floor(sortedDataLen / 4)].d) / 2;
        var iqr = upperQuartile - lowerQuartile; // inter-quartile range

        var lowerAdjacentValue = pv.min (data, function (d) { return d.d < (1.5 * iqr + lowerQuartile) ? d.d : 1000 * 60 * 60 * 24; });
        var upperAdjacentValue = pv.max (data, function (d) { return d.d > (1.5 * iqr + upperQuartile) ? 0 : d.d; });

        var outliers = sortedData.filter (function (d) { return d.d < lowerAdjacentValue || d.d > upperAdjacentValue });
        
        var xscale = pv.Scale.linear (0, sortedData[sortedDataLen - 1].d).range (0, width - 15).nice(); // -15 is to ensure any dots/txt overflowing doesn't get cut off

        var g = new pv.Panel()
            .canvas (el.id)
            .width (width)
            .height (height)
            .left(leftBuffer)
            .top(buffer)
            .right(buffer)
            .bottom(bottomBuffer);
        
        // the lower -> upper quartile box
        g.add (pv.Bar) 
            .data ( [ 1 ] )
            .top (0)
            .antialias(false)
            .height (height / 3 * 2 )
            .left (xscale (lowerQuartile))
            .width (xscale (upperQuartile - lowerQuartile))
            .fillStyle ('white')
            .strokeStyle ('black');

        // The lower -> uppoer adjacent value lines
        g.add (pv.Rule)
            .data ( [ { f: lowerAdjacentValue, t: lowerQuartile }, { f: upperQuartile, t: upperAdjacentValue } ] )
            .top (height / 3)
            .antialias(false)
            .left (function (d) { return xscale(d.f) })
            .width (function (d) { return xscale(d.t - d.f) });

        // outlier dots
        g.add (pv.Dot) 
            .data (outliers)
            .top (function (d) { return height / 3 + pv.random (-2, 2); })
            .left (function (a) { return xscale(a.d); })
            .fillStyle ('rgba(255,255,255, 0.4)')
            .strokeStyle ('black')
            .size (2);

        // Median dot
        g.add (pv.Dot) 
            .data ([ median ])
            .top (height / 3)
            .left (function (a) { return xscale(a); })
            .fillStyle (this.defaultColors)
            .strokeStyle (this.defaultColors)
            .title (function (a) { return 'Median: ' + xscale.tickFormat(a) + 'ms, Mean: ' + xscale.tickFormat(mean) + 'ms'; });

        g.add (pv.Rule)
            .data ( xscale.ticks() )
            .antialias(false)
            .left (function (d) { return xscale(d); })
            .bottom (-5)
            .height (5)
            .anchor ('bottom')
            .add (pv.Label)
            .text (function (d) { return xscale.tickFormat(d) + 'ms'; });

        g.root.render();
    }
});

/******************************************************************************
 * Line graph showing transactions per second.
 *****************************************************************************/
jarvis.graph.TpsGraph = Ext.extend(jarvis.graph.Graph, {

    title: function () {
        return 'Average Transactions per Minute';
    },

    render: function (el, data, config) {

        var me = this;
        var elBox = el.getBox();

        width = elBox.width;
        height = width * (1 / 1.61803399);

        height = height > elBox.height && elBox.height > 0.25 * width ? elBox.height : height;

        buffer = 35;

        var maxTransactions = pv.max(data, function (x) { return x.c; });
        maxTransactions = maxTransactions > 0 ? maxTransactions : 1;

        xscale = pv.Scale.linear (0, data.length).range (0, width - buffer * 2);
        yscale = pv.Scale.linear (0, maxTransactions).range (0, height - buffer * 2).nice();


        var g = new pv.Panel()
            .canvas (el.id)
            .width (width - buffer * 2)
            .height (height - buffer * 2)
            .left(buffer)
            .top(buffer)
            .right(buffer)
            .bottom(buffer);

        var barwidth = xscale(1) - xscale(0) > 4 ? Math.round((xscale(1) - xscale(0)) / 2) : 1;

        var yticks = yscale.ticks();
        if (yscale (yticks [yticks.length - 1]) - yscale(maxTransactions) < -10 ) {
            yticks.push (maxTransactions);
        } else if (yscale (yticks [yticks.length - 1]) - yscale(maxTransactions) > 10 ) {
            yticks [yticks.length - 2] = maxTransactions;
            yticks.pop();
        } else {
            yticks [yticks.length - 1] = maxTransactions;
        }

        g.add (pv.Rule)
            .data (yticks)
            .antialias(false)
            .left (-5)
            .width (function (d) { return this.index == 0 ? width - buffer * 2 + 5 : 5; })
            .bottom (function (d) { return yscale (d); })
            .anchor ('left')
            .add (pv.Label)
            .text (function (d) { return Math.round(d * 100) / 100 });

        // Find change of days 
        var dateChangeIndexes = [];
        var hourPoints = [];
        var currentDate = -1;
        var index = 0;
        data.map (function (d) {
            var d = Date.fromJulian (d.t);
            var day = d.format('j');
            if (day != currentDate) {
                dateChangeIndexes.push (index);
                currentDate = day;
            } else {
                var h = d.format('G') * 1;
                var m = d.format('i') * 1;

                if (h % 2 == 0 && m == 0) {
                    hourPoints.push (index);
                }
            }
            ++index;
        });

        // Day changes
        var lastDate = new Date(0);
        if (dateChangeIndexes.length > 1 && xscale(dateChangeIndexes[1]) - xscale(dateChangeIndexes[0]) < 70) {
            lastDate = Date.fromJulian (data[dateChangeIndexes[0]]);
            dateChangeIndexes.shift();
        }

        g.add (pv.Rule)
            .data (dateChangeIndexes)
            .antialias(false)
            .left (function (d) { return xscale (d); })
            .bottom (-30)
            .height (30)
            .anchor ('bottom')
            .add (pv.Label)
            .textAlign ('left')
            .textBaseline ('bottom')
            .text (function (d) { 
                if (this.index == dateChangeIndexes.length - 1) {
                    return '';
                }
                var date = Date.fromJulian(data[d].t);
                var format = 'D dS';
                if (date.format('y') != lastDate.format('y')) {
                    format = 'D dS M y';
                } else if (date.format('M') != lastDate.format('M')) {
                    format = 'D dS M';
                }
                lastDate = date;
                return date.format(format); 
            });

        // hour changes - only main times
        // If hours are not far apart, don't show times
        var showHourText = !(hourPoints.length > 1 && xscale(hourPoints[1]) - xscale(hourPoints[0]) < 20);
            
        g.add (pv.Rule)
            .data (hourPoints)
            .antialias(false)
            .left (function (d) { return xscale (d); })
            .bottom (-5)
            .height (5)
            .anchor ('bottom')
            .add (pv.Label)
            .text (function (d) { 
                if (showHourText) {
                    var date = Date.fromJulian(data[d].t);
                    return date.format('ga');
                } else {
                    return '';
                }
            });

        var highlightColor = '#080';

        var innerp = g.add (pv.Panel)
                .def ('i', -1)
                .def('x', function () { return xscale; });

        if (barwidth < 2) {
            innerp.add (pv.Area)
                .data (data) 
                .left (function (d) { return xscale(this.index); })
                .height (function (d) { return yscale(d.c); })
                .width (barwidth)
                .bottom (0)
                .fillStyle (this.defaultColors)
                .title (function (d) {
                    var date = Date.fromJulian(d.t);
                    return 'For ' + date.format ('g:ia') + ': avg: ' + Math.round(d.c * 100) / 100;
                });

            innerp.add(pv.Dot)
                .visible(function() { return innerp.i() >= 0 })
                .left(function() { return xscale(innerp.i()); })
                .bottom(function(d) { var c = data[innerp.i()]; return yscale(c ? c.c : 0); })
                .fillStyle("green")
                .strokeStyle(null)
                .size(8)
                .anchor ('top').add (pv.Label)
                .text (function (d) {
                    var c = data[innerp.i()];
                    if (c) {
                        var date = Date.fromJulian(c.t);
                        return date.format ('g:ia') + ': ' + (Math.round(c.c * 100) / 100);
                    }
                    return '';
                });


            innerp.add(pv.Bar)
                .fillStyle("rgba(0,0,0,.001)")
                .event("mouseout", function() { return innerp.i(-1) })
                .event("mousemove", function() { return innerp.i(innerp.x().invert(innerp.mouse().x) >> 0) })
                .event ('click', function () {
                    var c = data[innerp.i()];
                    if (c) {
                        me.fireEvent ('click', c);
                    }
                });

        } else {
            innerp.add (pv.Bar)
                .data (data) 
                .left (function (d) { return xscale(this.index); })
                .height (function (d) { return yscale(d.c); })
                .width (barwidth)
                .bottom (0)
                .fillStyle (this.defaultColors)
                .anchor ('top').add (pv.Dot)
                .size (8)
                .visible(function (d) { return this.index == innerp.i(); })
                .fillStyle (highlightColor)
                .strokeStyle(null)
                .anchor ('top').add (pv.Label)
                .text (function (d) {
                    var date = Date.fromJulian(d.t);
                    return date.format ('g:ia') + ': ' + (Math.round(d.c * 100) / 100);
                });

            // This is an invisible clickable bar that's big enough to click, and shows the highlighted 
            // point in time.
            innerp.add (pv.Bar)
                .def ('i', -1)
                .data (data) 
                .left (function (d) { return xscale(this.index); })
                .height (height - buffer * 2)
                .width (xscale(1) - xscale(0))
                .bottom (0)
                .fillStyle (pv.color ('#fff').alpha(0.01))
                .event ('mouseover', function (d) {
                    return innerp.i(this.index);
                })
                .event ('mouseout', function (d) {
                    return innerp.i(-1);
                })
                .event ('click', function (d) {
                    me.fireEvent ('click', d);
                })
        }

        g.root.render();
    }

});
