/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a summary page, summarising all of this jarvis's install.
 */


(function () {
return function () {

    var recentErrorsStore = new Ext.data.JsonStore ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('recent_errors'), method: 'GET' }),
        autoLoad: true,
        root: 'data',
        idProperty: 'id',
        fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'message'],
        listeners: {
            'loadexception': jarvisLoadException
        }
    });

    var recentErrorsList = new Ext.grid.GridPanel({
        store: recentErrorsStore,
        title: "Recent Errors: All Applications",
        columns: [
            {
                header: 'Event Time',
                dataIndex: 'start_time',
                sortable: true,
                width: 30,
                renderer: function(x) { return Date.parseDate(x, 'c').format ('D jS M Y H:i:s'); }
            },
            {
                header: 'Application',
                dataIndex: 'app_name',
                sortable: true,
                width: 30
            },
            {
                header: 'User',
                dataIndex: 'username',
                width: 20,
                sortable: true
            },
            {
                header: 'Error',
                dataIndex: 'message',
                sortable: false,
                renderer: function (x) { return x.substring (0, 60) + "..."; }
            }
        ],
        viewConfig: {
            forceFit: true
        },
        sm: new Ext.grid.RowSelectionModel({singleSelect:true})
    });

    var eastAccordion = new Ext.Panel({
        region: 'east',
        layout: 'accordion',
        split: true,
        collapsible: true,
        width: 600,
        title: "Recently",
        items: [
            recentErrorsList,
            {
                title: 'bla',
                html: 'help'
                }
        ]
    });

    var tps = {
        xtype: 'Visualisation',
        region: 'center',
        dataSource: {
            dataset: "tps",
        },
        graph: new jarvis.graph.TpsGraph(),
        graphConfig: {
            timeframe: trackerConfiguration.defaultDateRange.clone()
        }
    };

    return new Ext.Panel ({
        title: "Applications",
        layout: 'border',
        hideMode: 'offsets',
        items: [
            eastAccordion,
            tps,
        ]
    });

}; })();
