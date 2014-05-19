Ext.onReady (function () {
    jarvisInit ('demo');

    // Page size for paging
    var page_size = 25;

    // Do we want to pre-load a specific country?
    var boat_class = jarvisHashArg (document.URL, 'boat_class', '');

    // What to do after saving: 'detail', 'page'
    var action_after_saving = null;

    // If paging, what params?
    var page_params = {};

    // create the sub-set Data Store for the link_section pulldown
    var boat_class_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('boat_class'),
        autoLoad: true,
        root: 'data',
        idProperty: 'class',
        fields: ['class'],
        listeners: {
            'load' : function (store, records, options) {
                var r = new Ext.data.Record ({});
                r.set ('class', '');
                store.insert (0, [r]);

                boat_class_filter.setValue (boat_class);
                if (boat_class) {
                    reloadList ();
                }
            },
            'exception': jarvisProxyException
        }
    });

    // create the main Data Store for the boat list
    var boat_store = new Ext.data.JsonStore ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('boat'), method: 'GET' }),
        root: 'data',
        idProperty: 'id',
        totalProperty: 'fetched',
        fields: ['id', 'name', 'class', 'registration_num', 'owner' ],
        pruneModifiedRecords: true,
        listeners: {
            'beforeload': function () {
                grid.setDisabled (true);
            },
            'load': function () {
                setButtons ();
                grid.setDisabled (false);
            },
            'exception': jarvisProxyException,
            'write' : function (store, record) {
                grid.buttons[1].setText ('&nbsp;<b>UPDATING...</b>');
                var ttype = record.get ('_deleted') ? 'delete' : ((record.get('id') == 0) ? 'insert' : 'update');
                jarvisSendChange (ttype, store, 'boat', record);
            },
            'writeback' : function (store, result, ttype, record, remain) {
                remain || (grid.buttons[1].setText ('&nbsp'));
                store.handleWriteback (result, ttype, record, remain);
                setButtons ();
                remain || (action_after_saving = null);
            }
        }
    });

    // Function to edit the currently selected item in the grid.
    function editDetails () {
        var rowcol = grid.getSelectionModel().getSelectedCell();
        if (rowcol != null) {
            var r = boat_store.getAt (rowcol[0]);
            if (r.get('id') != '') {
                location.href = 'boat_detail.html#id=' + r.get('id');
            }
        }
    }

    // Paging widget.
    var pagingBar = new Ext.PagingToolbar({
        pageSize: page_size,
        store: boat_store,
        displayInfo: true,
        displayMsg: 'Displaying rows {0} - {1} of {2}',
        emptyMsg: "No data to display",
        listeners: {
            'beforechange': function (pbar, params) {
                // No changes pending, fine just load next page.
                if (! haveChanges()) return true;

                // Pages pending, these MUST be saved before we page.
                action_after_saving = 'page';
                page_params = params;

                grid.stopEditing();
                boat_store.writeChanges ();

                return false;
            }
        }
    });

    // create the grid
    var grid = new Ext.grid.EditorGridPanel({
        disabled: true,
        store: boat_store,
        columns: [
            {
                header: "Class",
                width: 120,
                dataIndex: 'class',
                sortable: true,
                editor: new Ext.form.ComboBox({
                    store: boat_class_store,
                    mode: 'local',
                    triggerAction: 'all',
                    displayField: 'class',
                    valueField: 'class',
                    forceSelection: true
                })
            },{
                header: "Name",
                width: 120,
                dataIndex: 'name',
                sortable: true,
                editor: new Ext.form.TextField({ allowBlank: false })
            },{
                header: "Reg #",
                width: 60,
                dataIndex: 'registration_num',
                sortable: true,
                editor: new Ext.form.TextField({ allowBlank: true })
            },{
                header: "Owner",
                width: 120,
                dataIndex: 'owner',
                sortable: true,
                editor: new Ext.form.TextField({ allowBlank: true })
            }
        ],
        renderTo:'extjs', width: 780, height: 400, viewConfig: {
            forceFit:true,
            getRowClass: function (r, rowIndex, rp, ds) { return r.get('_deleted') ? 'x-grid3-deleted-row' : '' }
        },
        tbar: [
            {
                text: 'New',
                iconCls:'add',
                handler: function () {
                    var boat_class = boat_class_filter.getValue ();
                    var r = new Ext.data.Record ({ });
                    r.set ('id', 0);
                    r.set ('name', '');
                    r.set ('class', boat_class);
                    r.set ('registration_num', '');
                    r.set ('owner', '');
                    boat_store.insert (0, r);
                    grid.startEditing (0, 0)
                    setButtons ();
                }
            },{
                text: 'Delete', iconCls:'remove', id: 'delete',
                handler: function () {
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = boat_store.getAt (rowcol[0]);
                        if (r.get('id') == 0) {
                            boat_store.remove (r);

                        } else if (! r.get ('_deleted')) {
                            r.set ('_deleted', true);
                        }
                        setButtons ();
                    }
                }
            }
        ],
        bbar: pagingBar,
        buttonAlign: 'left',
        buttons: [
            { text: 'Help', iconCls:'help', handler: function () { helpShow (); } },
            { xtype: 'tbtext', width: 300 },
            { xtype: 'tbfill' },
            {
                text: 'Classes', iconCls:'prev',
                handler: function () {
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    location.href = 'boat_class.html';
                }
            }, {
                text: 'Edit Details', id: 'detail',
                iconCls:'detail',
                handler: function () {
                    if (haveChanges ()) {
                        action_after_saving = 'detail';
                        grid.stopEditing();
                        boat_store.writeChanges ();

                    } else {
                        editDetails ();
                    }
                }
            }, {
                text: 'Save Changes', iconCls:'save', id: 'save',
                handler: function () {
                    grid.stopEditing();
                    boat_store.writeChanges ();
                }
            }, {
                text: 'Reload', iconCls:'reload',
                handler: function () {
                    grid.stopEditing ();
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    boat_store.reload ();
                }
            }
        ],
        listeners: {
            'beforeedit': function (e) { return (! e.record.get ('_deleted')); },
            'afteredit': function () { setButtons () },
            'cellclick': function () { setButtons () }
        }
    });

    // A simple class name filter.
    var boat_class_filter = new Ext.form.ComboBox ({
        id: 'boat_class_filter',
        store: boat_class_store,
        lazyInit: false,
        mode: 'local',
        triggerAction: 'all',
        displayField: 'class',
        valueField: 'class',
        forceSelection: true,
        valueNotFoundText: '<Select Boat Class...>',
        listeners: { 'select':
            function (combo, record, index) {
                boat_class = record.get ('class');
                location.replace (location.pathname + '#' + (boat_class ? 'boat_class=' + boat_class : ''));

                reloadList ();
            }
        }
    });
    grid.getTopToolbar().addFill ();
    grid.getTopToolbar().addText ('Boat Class: ');
    grid.getTopToolbar().addField (boat_class_filter);
    grid.getTopToolbar().doLayout ();

    // Reload according to current search critera.  Store params in baseParams.
    function reloadList () {
        var params = {};
        params.boat_class = boat_class || null;
        boat_store.baseParams = params;
        boat_store.load ({params: {start: 0, limit: page_size}});
    }

    //-------------------------------------------------------------------------
    // HAVE CHANGES FUNCTION
    //-------------------------------------------------------------------------
    function haveChanges () {
        return (boat_store.getModifiedRecords().length > 0);
    }

    //-------------------------------------------------------------------------
    // SET BUTTONS FUNCTION
    //-------------------------------------------------------------------------
    // Button dis/enable controls.
    function setButtons () {
        var haveModifiedRecords = haveChanges ();
        var selectedRowCol = grid.getSelectionModel().getSelectedCell();
        var selectedRecord = selectedRowCol && boat_store.getAt (selectedRowCol[0]);

        // Action after saving?
        if (! haveModifiedRecords && (action_after_saving != null)) {
            if (action_after_saving == 'detail') {
                editDetails ();

            } else if (action_after_saving == 'page') {
                boat_store.load ({'params': page_params});
            }
        }

        var exists = selectedRecord && ! selectedRecord.get('_deleted');
        boat_class_filter.setDisabled (haveModifiedRecords);
        Ext.ComponentMgr.get ('delete').setDisabled (! exists);
        Ext.ComponentMgr.get ('detail').setDisabled (! exists);
        Ext.ComponentMgr.get ('save').setDisabled (! haveModifiedRecords);
    }

    //-------------------------------------------------------------------------
    // MAIN PROGRAM
    //-------------------------------------------------------------------------
    // Load our help system.
    helpInit ('boat', 'Demo: Boats - Help');

    // Check for unsaved changes on all links.
    for (var i = 0; i < document.links.length; i++) {
        if (document.links[i].href.match (/#$/)) continue;
        document.links[i].onclick = function () {
            return (! haveChanges () || confirm ("Really discard unsaved changes?"));
        }
    }

    // Load boats now if we are loading Select Class.  Otherwise, wait for the
    // boat class list to load, and we will change the boat loading off that.
    //
    if (! boat_class) {
        reloadList ();
    }
});
