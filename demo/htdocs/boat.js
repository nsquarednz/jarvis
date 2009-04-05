Ext.onReady (function () {
    jarvisInit ('demo');

    // Do we want to pre-load a specific class?
    var url = document.URL;
    var args = Ext.urlDecode (url.substring(url.indexOf('?')+1, url.length));
    var preload_class = args.class || '';

    // Stores the current forced_title ('' if not forced).  Used when creating
    // new rows.
    var forced_title = '';

    // create the main Data Store for the boat list
    var boat_store = new Ext.data.JsonStore ({
        url: jarvisPostUrl (),              // We will use POST because we add extra params.
        root: 'data',
        idProperty: 'id',
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
            'loadexception': jarvisLoadException,
            'remove' : function (store, record, index) {
                if (record.get('id') != 0) {
                    grid.getTopToolbar().items.get (2).getEl ().innerHTML = '&nbsp;<b>DELETING...</b>';
                    jarvisSendChange ('delete', store, 'boat', record);
                }
            },
            'update' : function (store, record, operation) {
                if (operation == Ext.data.Record.COMMIT) {
                    grid.getTopToolbar().items.get (2).getEl ().innerHTML = '&nbsp;<b>UPDATING...</b>';
                    jarvisSendChange (((record.get ('id') == 0) ? 'insert' : 'update'), store, 'boat', record);
                }
                setButtons ();
            },
            'writeback' : function (store, result) {
                grid.getTopToolbar().items.get (2).getEl ().innerHTML = '&nbsp';
                if (result.success != 1) {
                    store.reload ();
                    alert (result.message);

                } else if (result.data != null) {
                    for (i=0; i<result.data.length; i++) {
                        store.getById (result.data[i]._record_id).data.id = result.data[i].id; // DB ID returned on INSERT.
                    }
                    setButtons ();
                }
            }
        }
    });

    // create the sub-set Data Store for the link_section pulldown
    var boat_class_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('fetch', 'boat_class'),      // This is a simple GET, we have no extra params.
        root: 'data',
        idProperty: 'class',
        fields: ['class', 'heading', 'forced_title'],
        listeners: {
            'load' : function () {
                if (boat_class_filter.store.getCount() > 0) {

                    // Figure which boat to select in the combo box.  If the URL specifies
                    // ?class=<class> then preload that one.  Otherwise just load the first one.
                    var record_idx = boat_class_filter.store.find ('class', preload_class);
                    if (record_idx < 0) {
                        record_idx = 0;
                    }
                    preload_class = '';

                    // Get the corresponding record, and load it into the ComboBox.
                    var record = boat_class_filter.store.getAt (record_idx);
                    var class = record.get ('class');
                    boat_class_filter.setValue (class);

                    // Fire the select event, which will load the main grid.
                    boat_class_filter.fireEvent ('select', boat_class_filter, record, 0);
                }
            },
            'loadexception': jarvisLoadException
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
        renderTo:'boat_grid',
        width: 780,
        height: 400,
        viewConfig: {
            forceFit:true
        },
        tbar: [
            {
                text: 'New',
                iconCls:'add',
                handler: function () {
                    var class = boat_class_filter.getValue (class);
                    if (class == '') {
                        return;
                    }
                    var r = new Ext.data.Record ({ });
                    r.set ('id', 0);
                    r.set ('class', class);
                    r.set ('published', new Date());
                    r.set ('title', forced_title);
                    r.set ('draft', 'DRAFT');
                    r.set ('warning_flag', '');
                    boat_store.insert (0, r);
                    grid.startEditing (0, (forced_title == '') ? 2 : 1)
                    setButtons ();
                }
            },
            {
                text: 'Delete',
                iconCls:'remove',
                handler: function () {
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = boat_store.getAt (rowcol[0]);
                        if (r.get('id') != 0) {
                            if (boat_store.getModifiedRecords().length > 0) {
                                alert ('Cannot delete with uncommitted changes pending.');
                                return;
                            }
                            if (! confirm ("Really delete entry: '" + Ext.util.Format.date (r.get('published'), 'Y-m-d') + "'")) {
                                return;
                            }
                        }
                        boat_store.remove (r);
                    }
                    setButtons ();
                }
            },
            {xtype: 'tbtext', text: '&nbsp;'}
        ],
        buttons: [
            {
                text: 'Edit Details',
                iconCls:'detail',
                handler: function () {
                    if (boat_store.getModifiedRecords().length > 0) {
                        alert ('Cannot edit details with uncommitted changes pending.');
                        return;
                    }
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = boat_store.getAt (rowcol[0]);
                        if (r.get('name') != 0) {
                            location.href = 'boat_detail.html?id=' + r.get('id');
                        }
                    }
                }
            },
            {
                text: 'Save Changes',
                iconCls:'save',
                handler: function () {
                    grid.stopEditing();
                    boat_store.commitChanges ();
                }
            },
            {
                text: 'Discard & Reload',
                iconCls:'remove',
                handler: function () {
                    grid.stopEditing ();
                    boat_store.reload ();
                }
            }
        ],
        listeners: {
            'cellclick': function () { setButtons () }
        }
    });

    // A simple name filter.
    var boat_class_filter = new Ext.form.ComboBox ({
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
                var params = new jarvisPostParams ('fetch', 'boat')
                params.class = record.get ('class');
                boat_store.load ({'params': params});
            }
        }
    });
    grid.getTopToolbar().addFill ();
    grid.getTopToolbar().addText ('Boat Class: ');
    grid.getTopToolbar().addField (boat_class_filter);

    // Button dis/enable controls.
    function setButtons () {
        var haveModifiedRecords = (boat_store.getModifiedRecords().length > 0);
        var selectedRowCol = grid.getSelectionModel().getSelectedCell();
        var selectedRowIsNewborn = ((selectedRowCol != null) && (boat_store.getAt (selectedRowCol[0]).get('id') == 0));

        if (selectedRowCol && (selectedRowIsNewborn || ! haveModifiedRecords)) {
            grid.getTopToolbar().items.get (1).enable ();
        } else {
            grid.getTopToolbar().items.get (1).disable ();
        }

        if (haveModifiedRecords) {
            grid.buttons[1].enable ();
            grid.buttons[2].enable ();
        } else {
            grid.buttons[1].disable ();
            grid.buttons[2].disable ();
        }
        if (selectedRowCol && ! selectedRowIsNewborn && ! haveModifiedRecords) {
            grid.buttons[0].enable ();
        } else {
            grid.buttons[0].disable ();
        }
    }

    // Load the boat store.  When it loads, it will pick a value in the list
    // and will load the matching items in the boat_store.
    boat_class_store.load ();
});
