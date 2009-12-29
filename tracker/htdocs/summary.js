/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a summary page, summarising all of this jarvis's install.
 */


(function () {
return function () {

    return new Ext.Panel ({
        title: "Summary",
        layout: 'fit',
        closable: true,
        items: [
            {
                xtype: 'Visualisation',
                dataSource: {
                    dataset: "tps",
                    params: {
                        from: new Date().add (Date.MINUTE, -1 * trackerConfiguration.defaultDateRange).getJulian(),
                        to: new Date().getJulian()
                    }
                },
                graph: new jarvis.graph.TpsGraph()
            }
        ]
    });

}; })();
