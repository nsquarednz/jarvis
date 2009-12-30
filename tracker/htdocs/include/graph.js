/**
 * Graphs
 */

// Base graph class
//
var jarvis = jarvis ? jarvis : {};
jarvis.graph = jarvis.graph ? jarvis.graph : {};

jarvis.graph.Graph = function () {
}


//
// Line graph showing transactions per second.
//
jarvis.graph.TpsGraph = Ext.extend(jarvis.graph.Graph, {

    title: function () {
        return "Average Transactions per Minute";
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

        var elBox = el.getBox();

        width = elBox.width;
        height = width * (1 / 1.61803399);

        if (height > elBox.height) {
            height = elBox.height;
        }

        buffer = 15;
        leftBuffer = 30;
        bottomBuffer = 30;

        var maxTransactions = pv.max(data, function (x) { return x.c; });
        maxTransactions = maxTransactions > 0 ? maxTransactions : 1;

        xscale = pv.Scale.linear (0, data.length).range (0, width - leftBuffer - buffer);
        yscale = pv.Scale.linear (0, maxTransactions).range (0, height - buffer - bottomBuffer).nice();


        var g = new pv.Panel()
            .canvas (el.id)
            .width (width - leftBuffer - buffer)
            .height (height - buffer - bottomBuffer)
            .left(leftBuffer)
            .top(buffer)
            .right(buffer)
            .bottom(bottomBuffer);

        g.add (pv.Bar)
            .data (data) 
            .left (function (d) { return xscale(this.index); })
            .height (function (d) { return yscale(d.c); })
            .width (1)
            .bottom (0)
            .title (function (d) {
                var date = Date.fromJulian(d.t);
                return date.format ('c') + ": average: " + Math.round(d.c * 100) / 100;
            });

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
            .left (-5)
            .width (5)
            .bottom (function (d) { return yscale (d); })
            .anchor ("left")
            .add (pv.Label)
            .text (function (d) { return Math.round(d * 100) / 100 });

/*
        var xa = new jarvis.graph.DateAxis()
                    .timeframe (config.timeframe)
                    .size (width - leftBuffer - buffer, bottomBuffer)
                    .valign ("bottom")
                    .offset (-1 * bottomBuffer)
                    .textStyle('black')
                    .addTo (g);
                    */

        // Find change of days 
        var dateChangeIndexes = [];
        var currentDate = 0;
        var index = 0;
        data.map (function (d) {
            if (Math.floor(d.t) != currentDate) {
                dateChangeIndexes.push (index);
                currentDate = Math.floor(d.t);
            }
            ++index;
        });

        var lastDate = new Date(0);
        g.add (pv.Rule)
            .data (dateChangeIndexes)
            .left (function (d) { return xscale (d); })
            .bottom (-5)
            .height (5)
            .anchor ("bottom")
            .add (pv.Label)
            .textAlign ('left')
            .text (function (d) { 
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

        g.root.render();
    }

});
