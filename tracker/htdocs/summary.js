/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a summary page, summarising all of this jarvis's install.
 */


(function () {
return function () {

    var recentErrorsStore = new Ext.data.Store ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('recent_errors'), method: 'GET' }),
        autoLoad: true,
        reader: new Ext.data.JsonReader ({
            root: 'data',
            id: 'id',
            totalProperty: 'fetched',
            fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'message'],
        }),
        listeners: {
            'loadexception': jarvisLoadException
        }
    });

    var recentErrorsList = new Ext.grid.GridPanel({
        store: recentErrorsStore,
        title: 'Recent Errors: All Applications',
        columns: [
            {
                header: 'Event Time',
                dataIndex: 'start_time',
                sortable: true,
                width: 50,
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
                renderer: function (x) { return Ext.util.Format.ellipsis (x, 60); }
            }
        ],
        viewConfig: {
            forceFit: true
        },
        listeners: {
            rowdblclick: function (g, i) {
                var record = g.store.getAt (i);
                var path = record.get('app_name') + '/Errors?date=' + record.get ('start_time') + '&id=' + record.id;
                loadAndShowTabFromPath (path);
            }
        },
        sm: new Ext.grid.RowSelectionModel({singleSelect:true})
    });

    var eastAccordion = new Ext.Panel({
        region: 'east',
        layout: 'accordion',
        split: true,
        collapsible: true,
        width: 600,
        title: 'Recently',
        items: [
            recentErrorsList
        ]
    });

    var tps = {
        xtype: 'TimeBasedVisualisation',
        region: 'center',
        dataSource: {
            dataset: 'tps',
        },
        graph: new jarvis.graph.TpsGraph(),
        graphConfig: {
            timeframe: trackerConfiguration.defaultDateRange.clone()
        }
    };

    return new Ext.Panel ({
        title: 'Applications',
        layout: 'border',
        hideMode: 'offsets',
        items: [
            eastAccordion,
            tps,
        ]
    });

}; })();
