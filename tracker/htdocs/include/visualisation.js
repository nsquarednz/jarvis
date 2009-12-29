/**
 * A ExtJS component for displaying a visualisation
 *
 * This doesn't do much of anything yet, it mostly just
 * exists for extension purposes later.
 */
Ext.ux.Visualisation = Ext.extend(Ext.Panel, {


    renderGraph: function (target) {
        if (target.rendered && this.data) {
            this.graph.render(target.id, this.data);
            this.setTitle (this.graph.title());
            console.log(this);
        } else if (this.data && !target.rendered) {
            this.doLayout(); // TODO: I have no idea why this is necessary, but it forces the
                             // data visualisation panel to be drawn. Without this call, it isn't 
                             // drawn until the user resizes their browser viewport.
        }
    },

    initComponent: function () {
        var me = this;

        Ext.apply (this, {
            header: true,
            items: [
                new Ext.BoxComponent ({
                    autoEl: { tag: 'div', cls: 'data-visualisation' }
                    , id: 'dv'
                    , anchor: '100% 100%'
                    , listeners: {
                        render: function () { me.renderGraph(this); }
                    }
                })
            ]
        });

        Ext.ux.Visualisation.superclass.initComponent.apply(this, arguments);

        console.log(this);

        // get the data for the component.
        Ext.Ajax.request({
            url: jarvisUrl (this.dataSource.dataset),
            params: this.dataSource.params,
            method: "GET",

            // We received a response back from the server, that's a good start.
            success: function (response, request_options) {
                me.data = Ext.util.JSON.decode (response.responseText).data;
                me.renderGraph(me.items.get('dv'));
            }
        });
    }

});

Ext.reg('Visualisation', Ext.ux.Visualisation);





