/**
 * Description: A ExtJS component for displaying a visualisation -
 *              a graph drawn with protovis.
 *
 *              The visualisation component can be created along
 *              the following lines:
 *
    var v = {
        xtype: 'Visualisation',
        dataSource: {
            dataset: "tps",
        },
        graph: new jarvis.graph.TpsGraph(),
        graphConfig: {
            timeframe: trackerConfiguration.defaultDateRange.clone()
        }
    };
    
 *              The visualisation code loads the datasource information
 *              and then using the 'graph' object renders the 
 *              graph to an inner component (basically a div). The
 *              graphConfig is passed through to the graph rendering
 *              code.
 *
 *              The code automatically will pass some of the graph
 *              config through to the data source as well - specifically
 *              it:
 *                  * converts the graph timeframe into 'from' and 'to'
 *                    parameters (in Julian date format).
 *
 *              This is a specific design for this application of course,
 *              not meant to be generic. If the dataSource is passed
 *              through with a pre-existing params object, then this
 *              auto-creation is not done.
 *
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
Ext.ux.Visualisation = Ext.extend(Ext.Panel, {

    renderGraph: function (target) {
        if (target.rendered && this.data) {
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
                if (this.graphConfig.timeframe) {
                    params.from = this.graphConfig.timeframe.from().formatForServer();
                    params.to = this.graphConfig.timeframe.to().formatForServer();
                }
            }
        }

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
