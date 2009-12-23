Ext.onReady (function () {
    jarvisInit ('demo');

    // create the main Data Store for the item types
    var user_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('users'),
        root: 'data',
        idProperty: 'id',
        fields: ['id', 'name', 'password', 'is_admin'],
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
                jarvisSendChange (ttype, store, 'users', record);
            },
            'writeback' : function (store, result, ttype, record, remain) {
                remain || (grid.buttons[1].getEl().innerHTML = '&nbsp');
                store.handleWriteback (result, ttype, record, remain);
                setButtons ();
            }
        }
    });

    // main grid
    var grid = new Ext.grid.EditorGridPanel({
        id: 'user_grid',
        disabled: true,
        store: user_store,
        columns: [
            {
                header: "Username",
                dataIndex: 'name',
                sortable: true,
                width: 200,
                editor: new Ext.form.TextField({ allowBlank: false })
            },{
                header: "Password",
                dataIndex: 'password',
                sortable: true,
                width: 40,
                editor: new Ext.form.TextField({ allowBlank: false })
            },{
                header: "Admin?",
                dataIndex: 'is_admin',
                sortable: true,
                width: 24,
                renderer: renderCheckbox
            }
        ],
        renderTo:'extjs', width: 780, height: 400, viewConfig: { forceFit:true },
        tbar: [
            {
                text: 'New',
                iconCls:'add',
                handler: function () {
                    var r = new Ext.data.Record ({ });
                    r.set ('id', 0);
                    r.set ('name', '');
                    r.set ('password', '');
                    r.set ('is_admin', 0);
                    user_store.insert (0, r);
                    grid.startEditing (0, 0);
                    setButtons ();
                }
            }, {
                text: 'Delete', iconCls:'remove', id: 'delete',
                handler: function () {
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = user_store.getAt (rowcol[0]);
                        if (r.get('id') == 0) {
                            user_store.remove (r);

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

                    var user = null;
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = user_store.getAt (rowcol[0]);
                        user = r.get ('class');
                    }
                    location.href = 'boat.html#' + (user ? 'user=' + user : '');
                }
            }, {
                text: 'Save Changes', iconCls:'save', id: 'save',
                handler: function () {
                    grid.stopEditing();
                    user_store.writeChanges ();
                }
            }, {
                text: 'Reload', iconCls:'reload',
                handler: function () {
                    grid.stopEditing ();
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    user_store.reload ();
                }
            }
        ],
        listeners: {
            'beforeedit': function (e) { return (! e.record.get ('_deleted')); },
            'afteredit': function () { setButtons () },
            'cellclick': function (grid, rowIdx, colIdx, e) {
                if (colIdx == 2) {
                    r = grid.getStore().getAt (rowIdx);
                    r.set ('is_admin', ! r.get ('is_admin'));
                    setButtons ()
                }
                setButtons ()
            }
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
        return (user_store.getModifiedRecords().length > 0);
    }

    //-------------------------------------------------------------------------
    // MAIN PROGRAM
    //-------------------------------------------------------------------------
    // Load our help system.
    helpInit ('user', 'Demo: Boat Class - Help');

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
        var selectedRecord = selectedRowCol && user_store.getAt (selectedRowCol[0]);
        var exists = selectedRecord && ! selectedRecord.get('_deleted');

        Ext.ComponentMgr.get ('delete').setDisabled (! exists);
        Ext.ComponentMgr.get ('save').setDisabled (! haveModifiedRecords);
    }

    user_store.load();
});
