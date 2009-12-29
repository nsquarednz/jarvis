/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a summary page for queries for an application.
 */


(function () {
return function (appName, extra) {

    return new Ext.Panel ({
        title: appName + "- Queries",
        layout: 'fit',
        closable: true,
        items: [
            {
                xtype: 'Visualisation',
                dataSource: {
                    dataset: "tps/" + appName,
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

