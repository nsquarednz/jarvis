/**
 * This provides a tab/panel for a summary of information
 * on errors from an application.
 */
(function () {
return function (appName) {

    // create the main Data Store for the fan list
    var recentErrorsStore = new Ext.data.JsonStore ({
        url: jarvisUrl ('errors/' + appName),
        autoLoad: true,
        root: 'data',
        idProperty: 'id',
        fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'message'],
        listeners: {
            'loadexception': jarvisLoadException
        }
    });

    var errorDetails = new Ext.Panel({
        layout: 'absolute',
        autoScroll: true,
        frame: true,
        columnWidth: 0.5,
        defaultType: 'label',
        anchor: '100% 100%',
        items: [
            {
                text: 'Event Time',
                x: 5, y: 5
            },
            {
                id: 'eventTime',
                x: 100, y: 5
            },
            {
                text: 'Username',
                x: 5, y: 25
            },
            {
                id: 'username',
                x: 100, y: 25
            },
            {
                text: 'User Groups',
                x: 250, y: 5
            },
            {
                id: 'groups',
                x: 355, y: 5
            },
            {
                text: 'SID',
                x: 250, y: 25
            },
            {
                id: 'sid',
                x: 355, y: 25
            },
            {
                text: 'Dataset',
                x: 550, y: 5
            },
            {
                id: 'dataset',
                x: 595, y: 5
            },
            {
                text: 'Error Message',
                x: 5, y: 45
            },
            new Ext.BoxComponent ({
                autoEl: {
                    tag: 'div'
                },
                id: 'message',
                anchor: '100% 100%',
                x: 100, y: 45
            })
        ]
    });

    var showErrorDetails = function(record) {
        console.log (record);
        console.log (errorDetails.items);
        errorDetails.items.get('eventTime').setText(record.get('start_time'));
        errorDetails.items.get('username').setText(record.get('username'));
        errorDetails.items.get('sid').setText(record.get('sid'));
        errorDetails.items.get('groups').setText(record.get('group_list'));
        errorDetails.items.get('dataset').setText(record.get('dataset') + " (" + record.get('action') + ")");

        errorDetails.items.get('message').el.insertHtml("afterBegin", "<code>" + record.get('message').replace (/\n/g, '<br>') + "</code>");
    };

    var recentErrorsList = new Ext.grid.GridPanel({
        store: recentErrorsStore,
        region: 'center', 
        columns: [
            {
                header: 'Event Time',
                dataIndex: 'start_time',
                sortable: true,
                width: 20,
                renderer: Ext.util.Format.dateRenderer ('D jS M Y H:i:s')
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
                renderer: function (x) { return x.substring (0, 100) + "..."; }
            }
        ],
        viewConfig: {
            forceFit: true
        },
        listeners: {
            cellclick: function (grid, rowIndex, columnIndex, e) {
                var record = grid.getStore().getAt(rowIndex);  // Get the Record
                showErrorDetails (record);
            }
        },
        sm: new Ext.grid.RowSelectionModel({singleSelect:true})
    });

    return new Ext.Panel ({
        title: appName + " - Errors",
        layout: 'border',
        closable: true,
        items: [
            recentErrorsList,
            new Ext.Panel ({
                layout: 'fit',
                region: 'south',
                title: 'Error Details',
                collapsible: true,
                height: 300,
                split: true,
                items: [
                    errorDetails
                ]
            })
        ]
    });

}; })();
