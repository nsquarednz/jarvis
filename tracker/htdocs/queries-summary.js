/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a summary page for queries for an application.
 */


(function () {
return function (appName, extra) {

    return new Ext.Panel ({
        title: appName + "- Queries",
        layout: 'border',
        hideMode: 'offsets',
        closable: true,
        items: [
            {
                xtype: 'Visualisation',
                region: 'center',
                dataSource: {
                    dataset: "tps/" + appName,
                },
                graph: new jarvis.graph.TpsGraph(),
                graphConfig: {
                    timeframe: trackerConfiguration.defaultDateRange.clone()
                }
            }
        ]
    });

}; })();

