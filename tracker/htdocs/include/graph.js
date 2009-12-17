/**
 * Graphs
 */

// Base graph class
//
var jarvis = jarvis ? jarvis : {};
jarvis.graph = jarvis.graph ? jarvis.graph : {};

jarvis.graph.Graph = function () {
}


// Line graph showing transactions per second.
//
jarvis.graph.TpsGraph = Ext.extend(jarvis.graph.Graph, {

    render: function (el, data) {
        var g = new pv.Panel()
            .canvas (el)
            .width (400)
            .height (300);

        g.add (pv.Line)
            .data (data) 
            .left (function (d) { return this.index })
            .bottom (function (d) { return d.c });

        g.root.render();
    }

});
