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
        return "15 Minute Averages of Transactions per Minute";
    },

    /*
     * Rendering function. Renders to 'el' with the given data
     * el is a Ext.Element object. Data is an array of data points,
     * graph specific.
     */
    render: function (el, data) {

        var elBox = el.getBox();

        width = 800; // TODO - it shouldn't be hard coded, but getting the extjs layout stuff to work's a PITA.
        height = width * (1 / 1.61803399);

        buffer = 15;
        leftBuffer = 30;
        bottomBuffer = 30;

        var maxTransactions = pv.max(data, function (x) { return x.c; });

        xscale = pv.Scale.linear (0, data.length).range (0, width - leftBuffer - buffer);
        yscale = pv.Scale.linear (0, maxTransactions).range (0, height - buffer - bottomBuffer).nice();

        var g = new pv.Panel()
            .canvas (el.id)
            .width (width)
            .height (height)
            .left(leftBuffer)
            .top(buffer)
            .right(buffer)
            .bottom(bottomBuffer);

        g.add (pv.Bar)
            .data (data) 
            .left (function (d) { return xscale(this.index); })
            .height (function (d) { return yscale(d.c); })
            .width (1)
            .bottom (0);

        var yticks = yscale.ticks();
        if (yscale (yticks [yticks.length - 1]) - yscale(maxTransactions) < -10 ) {
            yticks.push (maxTransactions);
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
            .text (function (d) { return Math.round(d * 100, 2) / 100 });

        // TODO - make pretty date/time - just like in V2
        g.add (pv.Rule)
            .data (xscale.ticks())
            .bottom (-5)
            .height (5)
            .left (function (d) { return xscale (d); })
            .anchor ("bottom")
            .add (pv.Label)
   //         .text (function (d) { console.log("looking at", d); return data [Math.floor(d)].d; });
            .text (function (d) { return data [Math.floor(d)].t.substring (11, 16); });

        g.root.render();
    }

});
