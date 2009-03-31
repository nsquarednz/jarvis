Ext.onReady (function () {
    jarvisInit ('demo');

    // create the main Data Store for the item types
    var boat_class_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('fetch', 'boat_class'),
        root: 'data',
        idProperty: 'id',
        fields: ['id', 'class', 'active', 'description'],
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
                    jarvisRemove (store, 'boat_class', record);
                }
            },
            'update' : function (store, record, operation) {
                if (operation == Ext.data.Record.COMMIT) {
                    grid.getTopToolbar().items.get (2).getEl ().innerHTML = '&nbsp;<b>UPDATING...</b>';
                    jarvisUpdate (store, 'boat_class', record);
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

    // this holds our staff names
    var staff_names_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('fetch', 'staff_names'),
        root: 'data',
        idProperty: 'id',
        fields: ['id', 'name']
    });

    // expander for the grid.
    var expander = new Ext.grid.RowExpander({
	lazyRender: true,
        dataFieldName: 'description',
        listeners: {
            // Needed because we have lazyRender = true.
            'expand': function (ex, record, body, rowIndex) {
                var content = expander.getWrappedBodyContent(record, rowIndex);
                content = content.replace (/\n/g, '<br>');
                body.innerHTML = content;
            }
        }
    });

    // create the grid
    var grid = new Ext.grid.EditorGridPanel({
        disabled: true,
        plugins: [ expander ],
        store: boat_class_store,
        columns: [
            expander,
            {
                header: "Class",
                width: 600,
                dataIndex: 'class',
                sortable: true,
                fixed: true,
                editor: new Ext.form.TextField({ allowBlank: false })
            },{
                header: "Active?",
                width: 80,
                fixed: true,
                dataIndex: 'active',
                sortable: true,
                editor: new Ext.form.ComboBox({
                    store: ['Y', 'N'],
                    mode: 'local',
                    triggerAction: 'all',
                    forceSelection: true,
                    editable: false
                })
            },
        ],
        renderTo:'boat_class_grid',
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
                    var r = new Ext.data.Record ({ });
                    r.set ('id', 0);
                    r.set ('class', '');
                    r.set ('active', 'N');
                    r.set ('description', 'Description is required.');
                    boat_class_store.insert (0, r);
                    grid.startEditing (0, 1);
                    setButtons ();
                }
            },
            {
                text: 'Delete',
                iconCls:'remove',
                handler: function () {
                    if (boat_class_store.getModifiedRecords().length > 0) {
                        alert ('Cannot delete with uncommitted changes pending.');
                        return;
                    }
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = boat_class_store.getAt (rowcol[0]);
                        if ((r.get('id') != 0) && (! confirm ("Really delete entry: '" + r.get('class') + '"'))) return;
                        boat_class_store.remove (r);
                    }
                    setButtons ();
                }
            },
            {xtype: 'tbtext', text: '&nbsp;'}
        ],
        buttons: [
            {
                text: 'View Boats',
                iconCls:'detail',
                handler: function () {
                    if (boat_class_store.getModifiedRecords().length > 0) {
                        alert ('Cannot view boats with uncommitted changes pending.');
                        return;
                    }
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = boat_class_store.getAt (rowcol[0]);
                        if (r.get('class') != '') {
                            location.href = 'boat.html?class=' + r.get('class');
                        }
                    }
                }
            },
            {
                text: 'Save Changes',
                iconCls:'save',
                handler: function () {
                    grid.stopEditing();
                    boat_class_store.commitChanges ();
                }
            },
            {
                text: 'Discard & Reload',
                iconCls:'remove',
                handler: function () {
                    grid.stopEditing ();
                    boat_class_store.reload ();
                }
            }
        ],
        listeners: {
            'cellclick': function () { setButtons () }
        }
    });

    // Create a custom editor to be used for the expander row.
    var editor = new Ext.grid.GridEditor(
        new Ext.form.TextArea({
            enterIsSpecial: false
        }),
        {
            completeOnEnter: false,
            cancelOnEsc: true,
            listeners: {
                'complete': function (ed, value) {
                    ed.grid.getStore().getAt(ed.row).set('description', value);
                },
                'show': function(ed) {
                    ed.field.setHeight(100);
                }

            }
        });

    // Assign the editor to the grid for the class of the expander row.
    grid.getEl().on(
        'dblclick',
        function(e) {
            editor.grid = this;
            editor.row = this.getView().findRowIndex(e.target);
            editor.startEdit(e.target, this.getStore().getAt(editor.row).get('description'));
        },
        grid,
        {delegate: '.x-grid3-row-body'});

    // Button dis/enable controls.
    function setButtons () {
        var haveModifiedRecords = (boat_class_store.getModifiedRecords().length > 0);
        var selectedRowCol = grid.getSelectionModel().getSelectedCell();
        var selectedRowIsNewborn = ((selectedRowCol != null) && (boat_class_store.getAt (selectedRowCol[0]).get('id') == 0));

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

    staff_names_store.load();
    boat_class_store.load();
});
