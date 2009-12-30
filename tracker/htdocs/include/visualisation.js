/**
 * A ExtJS component for displaying a visualisation
 *
 * This doesn't do much of anything yet, it mostly just
 * exists for extension purposes later.
 */
Ext.ux.Visualisation = Ext.extend(Ext.Panel, {

    renderGraph: function (target) {
        if (target.rendered && this.data) {
            console.log ("rendering graph");
            this.graph.render(target, this.data, this.graphConfig);
            this.setTitle (this.graph.title());
        } 
    },

    initComponent: function () {
        var me = this;
        this.dataVisualisationElementId = Ext.id();

        var dv = new Ext.BoxComponent ({
            autoEl: { tag: 'div', cls: 'data-visualisation', html: '&nbsp;' },
            id: this.dataVisualisationElementId,
            x: 0,
            y: 0,
            anchor: '100% 100%',
            listeners: {
                render: function () { me.renderGraph(this); }
            }
        });

        Ext.apply (this, {
            header: true,
            border: false,
            autoScroll: true,
            layout: 'fit',
            title: 'Loading data...',

            items: [
                dv
            ]
        });

        // When this component's resized, redraw the graph to fit
        // the setTimeout () is used to force the call to be 'later'
        // because otherwise the resize hasn't yet actually occurred
        // to the DOM element yet (the new size is passed in to the
        // resize handler, but the graph relies on the actual element
        // size.
        this.on ('resize', function () { setTimeout(function () { me.renderGraph(dv); }, 0); });

        Ext.ux.Visualisation.superclass.initComponent.apply(this, arguments);

        // Build the parameters list for the fetching. If we have parameters,
        // then use those, otherwise build one up, from configuration - this
        // code understands deeply the config - it's not generic.
        var params;
        if (this.dataSource.params) {
            params = this.dataSource.params;
        } else {
            params = {};
            if (this.graphConfig) {
                console.log (this.graphConfig, this.graphConfig.timeframe.toString());
                if (this.graphConfig.timeframe) {
                    params.from = this.graphConfig.timeframe.from().formatForServer();
                    params.to = this.graphConfig.timeframe.to().formatForServer();
                }
            }
        }

        console.log (params);

        // Fetch now the data for the component.
        Ext.Ajax.request({
            url: jarvisUrl (this.dataSource.dataset),
            params: params,
            method: "GET",

            // We received a response back from the server, that's a good start.
            success: function (response, request_options) {
                me.data = Ext.util.JSON.decode (response.responseText).data;
                me.renderGraph(me.items.get(me.dataVisualisationElementId));
            }
        });
    }

});

Ext.reg('Visualisation', Ext.ux.Visualisation);





