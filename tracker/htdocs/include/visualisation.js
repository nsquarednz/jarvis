/**
 * A ExtJS component for displaying a visualisation
 *
 * This doesn't do much of anything yet, it mostly just
 * exists for extension purposes later.
 */
Ext.ux.Visualisation = Ext.extend(Ext.BoxComponent, {

    //tpl: new Ext.Template ('<div></div>'),
    //

    autoEl: {
        tag: 'div',
        cls: 'data-visualisation'
    },

    onRender: function(ct) {
        Ext.ux.Visualisation.superclass.onRender.apply(this, arguments);
        this.renderGraph();
    },
    
    renderGraph: function () {
        if (this.rendered && this.data) {
            this.graph.render(this.id, this.data);
        }
    },

    initComponent: function () {
        Ext.ux.Visualisation.superclass.initComponent.apply(this, arguments);

        var me = this;

        // get the data for the component.
        Ext.Ajax.request({
            url: jarvisUrl (this.dataSource.dataset),

            // We received a response back from the server, that's a good start.
            success: function (response, request_options) {
                me.data = Ext.util.JSON.decode (response.responseText).data;
                me.renderGraph();
            }
        });
    }

});

Ext.reg('Visualisation', Ext.ux.Visualisation);





