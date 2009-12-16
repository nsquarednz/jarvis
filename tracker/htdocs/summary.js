/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a summary page, summarising all of this jarvis's install.
 */


(function () {

    return new Ext.Panel ({
        title: "Summary",
        layout: 'fit',
        closable: true,
        items: [
            {
                xtype: 'Visualisation',
                width: 600,
                height: 300,
                dataSource: {
                    dataset: "tps"
                },
                graph: new jarvis.graph.TpsGraph()
            }
        ]
    });


})();
