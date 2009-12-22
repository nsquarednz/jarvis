Ext.onReady (function () {
    jarvisInit ('demo');

    // create the main Data Store for the item types
    var boat_class_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('boat_class'),
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
            'write' : function (store, record) {
                grid.buttons[1].getEl().innerHTML = '&nbsp;<b>UPDATING...</b>';
                var ttype = record.get ('_deleted') ? 'delete' : ((record.get('id') == 0) ? 'insert' : 'update');
                jarvisSendChange (ttype, store, 'boat_class', record);
            },
            'writeback' : function (store, result, ttype, record, remain) {
                remain || (grid.buttons[1].getEl().innerHTML = '&nbsp');
                store.handleWriteback (result, ttype, record, remain);
                setButtons ();
            }
        }
    });

    // expander for the grid.
    var expander = new Ext.grid.RowExpander({
	lazyRender: true,
        dataFieldName: 'description',
        header: '&nbsp',
        listeners: {
            // Needed because we have lazyRender = true.
            'expand': function (ex, record, body, rowIndex) {
                var content = expander.getWrappedBodyContent(record, rowIndex);
                content = content.replace (/\n/g, '<br>');
                body.innerHTML = content;
            }
        }
    });

    // main grid
    var grid = new Ext.grid.EditorGridPanel({
        disabled: true,
        plugins: [ expander ],
        store: boat_class_store,
        columns: [
            expander,
            {
                header: "Class",
                dataIndex: 'class',
                sortable: true,
                width: 200,
                editor: new Ext.form.TextField({ allowBlank: false })
            },{
                header: "Active?",
                dataIndex: 'active',
                sortable: true,
                width: 40,
                editor: new Ext.form.ComboBox({
                    store: ['Y', 'N'],
                    mode: 'local',
                    triggerAction: 'all',
                    forceSelection: true,
                    editable: false
                })
            },
        ],
        renderTo:'extjs', width: 780, height: 400, viewConfig: { forceFit:true },
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
            }, {
                text: 'Delete', iconCls:'remove', id: 'delete',
                handler: function () {
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = boat_class_store.getAt (rowcol[0]);
                        if (r.get('id') == 0) {
                            boat_class_store.remove (r);

                        } else if (! r.get ('_deleted')) {
                            r.set ('_deleted', true);
                            grid.getView().getRow (rowcol[0]).className += ' x-grid3-deleted-row';
                        }
                        setButtons ();
                    }
                }
            }
        ],
        buttons: [
            { text: 'Help', iconCls:'help', handler: function () { helpShow (); } },
            new Ext.Toolbar.Fill (),
            {
                text: 'Boats', iconCls:'next',
                handler: function () {
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    location.href = 'boat.html#' + (country ? 'boat_class=' + country : '');
                }
            }, {
                text: 'Save Changes', iconCls:'save', id: 'save',
                handler: function () {
                    grid.stopEditing();
                    boat_class_store.writeChanges ();
                }
            }, {
                text: 'Reload', iconCls:'reload',
                handler: function () {
                    grid.stopEditing ();
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    boat_class_store.reload ();
                }
            }
        ],
        listeners: {
            'beforeedit': function (e) { return (! e.record.get ('_deleted')); },
            'afteredit': function () { setButtons () },
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

    //-------------------------------------------------------------------------
    // HAVE CHANGES FUNCTION
    //-------------------------------------------------------------------------
    function haveChanges () {
        return (boat_class_store.getModifiedRecords().length > 0);
    }

    //-------------------------------------------------------------------------
    // MAIN PROGRAM
    //-------------------------------------------------------------------------
    // Load our help system.
    helpInit ('boat_class', 'Demo: Boat Class - Help');

    // Check for unsaved changes on all links.
    for (var i = 0; i < document.links.length; i++) {
        document.links[i].onclick = function () {
            return (! haveChanges () || confirm ("Really discard unsaved changes?"));
        }
    }

    // Button dis/enable controls.
    function setButtons () {
        var haveModifiedRecords = haveChanges ();
        var selectedRowCol = grid.getSelectionModel().getSelectedCell();
        var selectedRecord = selectedRowCol && boat_class_store.getAt (selectedRowCol[0]);
        var exists = selectedRecord && ! selectedRecord.get('_deleted');

        Ext.ComponentMgr.get ('delete').setDisabled (! exists);
        Ext.ComponentMgr.get ('save').setDisabled (! haveModifiedRecords);
    }

    boat_class_store.load();
});
