/**
 * Description: ExtJS components for displaying visualisations -
 *              a graph drawn with protovis.
 *
 *              The visualisation component can be created along
 *              the following lines:
 *
    var v = {
        xtype: 'TimeBasedVisualisation',
        dataSource: {
            dataset: 'tps'
            // params: { } Only set if you have actual params to pass through.
        },
        graph: new jarvis.graph.TpsGraph(),
        graphConfig: {
            timeframe: trackerConfiguration.defaultDateRange.clone()
        }
    };
    
 *              The visualisation code loads the data source information
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
 *              not meant to be generic. 
 *
 *              If the dataSource is passed through with a pre-existing 
 *              params object, then this auto-creation is done in a way
 *              to not overwrite pre-defined param values.
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


/**
 * Description:  The Visualisation component is the base component that
 *               simplifies showing graphs drawn with protovis using data
 *               from the server.
 */
Ext.ux.Visualisation = Ext.extend(Ext.Panel, {

    /**
     * Default graph configuration object - empty. To be provided by
     * the creator of the component.
     */
    graphConfig: {},

    /**
     * Description:  This function renders the graph to the target element,
     *               which is a ExtJS Element object.
     *
     * Rendering of the graph occurs after rendering of the Visualisation
     * component, after a resize of the component, and after the data
     * for the graph is loaded.
     */
    renderGraph: function (target) {
        if (target.rendered && this.data) {
            this.graph.render(target, this.data, this.graphConfig);
            this.setTitle (this.graph.title());
        } 
    },

    /**
     * Description:  Override the initialisation of the component to 
     *               provide our own component elements. The creator
     *               of the Visualisation component can still pass in
     *               configuration, but we need to control key configuration
     *               - such as subelements.
     */
    initComponent: function () {
        var me = this;
        this.dataVisualisationElementId = Ext.id();

        // The graph is actually rendered to a sub-div element.
        var dv = new Ext.BoxComponent ({
            autoEl: { tag: 'div', cls: 'data-visualisation' },
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
            layout: 'fit',
            autoScroll: true,
            title: 'Loading...',
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

        this.loadGraphData();
    },

    /**
     * Description:  Loads the graph data. 
     *
     *               If dataSource.params exists, it uses these for the 
     *               parameters of the datasource.
     */
    loadGraphData: function () {
        var me = this;
        var url = jarvisUrl (this.dataSource.dataset);
        var myMask = null;

        if (this.body) {
            myMask = new Ext.LoadMask(this.body ? this.body : Ext.getBody(), {msg:"Please wait..."});
            myMask.show();
        }

        // Fetch now the data for the component.
        Ext.Ajax.request({
            url: url,
            params: this.dataSource.params ? this.dataSource.params : {},
            method: 'GET',

            // We received a response back from the server, that's a good start.
            success: function (response, request_options) {
                if (myMask)
                    myMask.hide();
                try {
                    me.data = Ext.util.JSON.decode (response.responseText).data;
                } catch (e) {
                    Ext.Msg.show ({
                        title: 'Data Parsing Error',
                        msg: 'Cannot understand data from server: ' + e,
                        buttons: Ext.Msg.OK,
                        icon: Ext.Msg.ERROR
                    });
                }
                me.renderGraph(me.items.get(me.dataVisualisationElementId));
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        });
    }

});

Ext.reg('Visualisation', Ext.ux.Visualisation);

/**
 * Description:  The TimeBasedVisualisation component is a Visualisation component that
 *               simplifies showing graphs based on a time span. It uses a pre-configured
 *               timespan to retrieve only a specific set of data from the server, and
 *               provides functions to the user in the footer of the Visualisation
 *               component's panel for choosing different timespans.
 *
 *               This component expects the default timeframe for the data the 
 *               visualisation shows to be provided in graphConfig.timeframe,
 *               and the dataset retrieved will be provided with from/to dates using
 *               parameters 'from' and 'to'.
 */
Ext.ux.TimeBasedVisualisation = Ext.extend(Ext.ux.Visualisation, {

    initComponent: function () {
        var me = this;

        // Provide some controls to allow the user to change the timespan the graph
        // data covers.
        Ext.apply (this, {
            bbar: [
                {
                    text: 'Show:',
                    xtype: 'label'
                },
                {
                    toggleGroup: 'visualisationDateRangeToggleGroup',
                    text: 'Last Day',
                    pressed: true,
                    handler: function () { me.alterGraphTimeframe (new jarvis.Timeframe('..now')); }
                },
                {
                    toggleGroup: 'visualisationDateRangeToggleGroup',
                    text: 'Last Week',
                    handler: function () { me.alterGraphTimeframe (new jarvis.Timeframe('...now')); }
                }
            ]
        });

        Ext.ux.TimeBasedVisualisation.superclass.initComponent.apply(this, arguments);
    },

    /**
     * Description:  Alters the timeframe of the graph, reloading the graph 
     *               data, and then once that is done, redrawing the graph.
     */
    alterGraphTimeframe: function(newTimeframe) {
        this.graphConfig.timeframe = newTimeframe;
        this.loadGraphData();
    },

    /**
     * Description:  Loads the graph data. This overrides the superclass method
     *               to set up the correct timeframe to retreive data over, and
     *               then calls the superclass loadGraphData() method.
     *
     * The timeframe (graphConfig.timeframe) is inserted into graphConfig.params.
     */
    loadGraphData: function () {
        var me = this;

        // Build the parameters list for the fetching. If we have parameters,
        // then use those, otherwise build one up, from configuration - this
        // code understands deeply the config - it's not generic.
        this.dataSource.params = this.dataSource.params || {};

        if (this.graphConfig.timeframe) {
            this.dataSource.params.from = this.graphConfig.timeframe.from().formatForServer();
            this.dataSource.params.to = this.graphConfig.timeframe.to().formatForServer();
        }

        Ext.ux.TimeBasedVisualisation.superclass.loadGraphData.apply(this, arguments);
    }
});

Ext.reg('TimeBasedVisualisation', Ext.ux.TimeBasedVisualisation);
