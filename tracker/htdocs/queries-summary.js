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
                width: 600,
                height: 300,
                dataSource: {
                    dataset: "tps/" + appName,
                    params: {
                        from: new Date().add (Date.DAY, -7).format('Y-m-d'),
                        to: new Date().format('Y-m-d')
                    }
                },
                graph: new jarvis.graph.TpsGraph()
            }
        ]
    });

}; })();

