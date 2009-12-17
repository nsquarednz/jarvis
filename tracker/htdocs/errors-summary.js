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
        fields: ['start_time', 'username', 'message'],
        listeners: {
            'loadexception': jarvisLoadException
        }
    });

    var expander = new Ext.grid.RowExpander({
        lazyRender: true,
        header: '&nbsp;',
        dataFieldName: 'message',
        listeners: {
            // Needed because we have lazyRender = true.
            'expand': function (ex, record, body, rowIndex) {
                var content = expander.getBodyContent(record, rowIndex);
                content = prettyPrintOne(content).replace (/\n/g, '<br>');
                body.innerHTML = "<code class='prettyprint'>" + content + "</code>";
            }
        }
    });

    var recentErrorsList = new Ext.grid.GridPanel({
        store: recentErrorsStore,
        plugins: [ expander ],
        columns: [
            expander,
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
        sm: new Ext.grid.RowSelectionModel({singleSelect:true})
    });


    return new Ext.Panel ({
        title: appName + " - Errors",
        layout: 'fit',
        closable: true,
        items: [
            recentErrorsList
        ]
    });

}; })();
