/**
 * Ext component to display a list of errors.
 *
 * You need to pass in a few pieces of information - when
 * creating this, pass in a 'dataSourceParams' map.
 * This should hold any necessary information (if any is required).
 */
Ext.ux.ErrorList = Ext.extend (Ext.Panel, {

    initComponent: function () {

        this.dataSourceParams = this.dataSourceParams || {};
        this.dataSourceParams.appName = this.dataSourceParams.appName || '';
        this.dataSourceParams.user = this.dataSourceParams.user || '';

        var errorsUrl = jarvisUrl ('errors/' + this.dataSourceParams.appName + '/' + this.dataSourceParams.user);

        if (this.dataSourceParams.limit) {
            errorsUrl = jarvisUrl ('recent_errors/' + this.dataSourceParams.appName + '/' + this.dataSourceParams.user);
        }

        // Create the main Data Store for the fan list
        var errorsStore = new Ext.data.Store ({
            proxy: new Ext.data.HttpProxy ({ url: errorsUrl, method: 'GET' }),
            autoLoad: true,
            baseParams: {
            },
            reader: new Ext.data.JsonReader ({
                root: 'data',
                id: 'id',
                totalProperty: 'fetched',
                fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'params', 'post_body', 'message']
            }),
            listeners: {
                'load': function (store) {
                    store.reload.defer(60 * 1000 * 5, store); // Reload automatically after a minute.
                },
                'loadexception': jarvis.tracker.extStoreLoadExceptionHandler
            }
        });

        var errorList = new Ext.grid.GridPanel({
            store: errorsStore,
            columns: [
                {
                    header: 'Event Time',
                    dataIndex: 'start_time',
                    sortable: true,
                    width: 25,
                    renderer: function(x) { 
                        var dte = Date.parseDate(x, 'c').format ('d/m H:i:s');
                        return '<span qtip="' + dte + '">' + prettyDate(Date.parseDate(x, 'c')) + '</span>';
                    }
                },
                {
                    header: 'User',
                    dataIndex: 'username',
                    width: 40,
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
            sm: new Ext.grid.RowSelectionModel({
                singleSelect:true,
                listeners: {
                    rowselect: function (sm, rowIndex, r) {
                        //showErrorDetails (r); // TODO
                    }
                }
            }),
            listeners: {
                rowdblclick: function (g, i) {
                    var record = g.store.getAt (i);
                    var path = record.get('app_name') + '/Errors?date=' + record.get ('start_time') + '&id=' + record.id;
                    jarvis.tracker.loadAndShowTabFromPath (path);
                }
            }
        });
     
        Ext.apply (this, {
            layout: 'fit',
            items: [
                errorList
            ],
            tools: [
                {
                    id: 'refresh',
                    qtip: 'Reload recent error list from the server',
                    handler: function () {
                        errorsStore.reload();
                    }
                }
            ]
        });

        Ext.ux.ErrorList.superclass.initComponent.apply(this, arguments);
    }
});

Ext.reg('ErrorList', Ext.ux.ErrorList);
