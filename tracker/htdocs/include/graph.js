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
        return "Transactions per Minute";
    },

    /*
     * Rendering function. Renders to 'el' with the given data
     */
    render: function (el, data) {

        width = 600;
        height = 500;

        buffer = 15;
        leftBuffer = 30;
        bottomBuffer = 30;

        var maxTransactions = pv.max(data, function (x) { return x.c; });

        xscale = pv.Scale.linear (0, data.length).range (0, width - leftBuffer - buffer);
        yscale = pv.Scale.linear (0, maxTransactions).range (0, height - buffer - bottomBuffer).nice();

        var g = new pv.Panel()
            .canvas (el)
            .width (width)
            .height (height)
            .left(leftBuffer)
            .top(buffer)
            .right(buffer)
            .bottom(bottomBuffer);

        g.add (pv.Area)
            .data (data) 
            .left (function (d) { return xscale(this.index); })
            .height (function (d) { return yscale(d.c); })
            .bottom (0);

        var yticks = yscale.ticks();
        if (yticks [yticks.length - 1] < maxTransactions) {
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

        g.add (pv.Rule)
            .data (xscale.ticks())
            .bottom (-5)
            .height (5)
            .left (function (d) { return xscale (d); })
            .anchor ("bottom")
            .add (pv.Label)
   //         .text (function (d) { console.log("looking at", d); return data [Math.floor(d)].d; });
            .text (function (d) { return data [Math.floor(d)].h + ':' + data [Math.floor(d)].m; });

        g.root.render();
    }

});
