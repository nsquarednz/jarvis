Ext.onReady (function () {
    jarvisInit ('demo');

    // create the main Data Store for the item types
    var user_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('users'),
        root: 'data',
        idProperty: 'id',
        fields: ['id', 'name', 'has_password', 'is_admin'],
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
                jarvisSendChange (ttype, store, 'users', record);
            },
            'writeback' : function (store, result, ttype, record, remain) {
                remain || (grid.buttons[1].setText ('&nbsp'));
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
                header: "Has Password",
                dataIndex: 'has_password',
                sortable: true,
                width: 40
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
                    r.set ('has_password', 'NO');
                    r.set ('is_admin', 0);
                    user_store.insert (0, r);
                    grid.startEditing (0, 0);
                    setButtons ();
                }
            },{
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
            },{
                text: 'Set Password', iconCls:'detail', id: 'password',
                handler: function () {
                    var rowcol = grid.getSelectionModel().getSelectedCell();
                    if (rowcol != null) {
                        var r = user_store.getAt (rowcol[0]);
                        if ((r.get('id') != 0) && ! r.get ('_deleted')) {
                            setPassword (r);
                        }
                    }
                }
            }
        ],
        buttonAlign: 'left',
        buttons: [
            { text: 'Help', iconCls:'help', handler: function () { helpShow (); } },
            { xtype: 'tbtext', width: 300 },
            { xtype: 'tbfill' },
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

    //-------------------------------------------------------------------------
    // SET PASSWORD
    //-------------------------------------------------------------------------
    var password_window = null;

    function setPassword (r) {
        if (! password_window) {
            password_window = new Ext.Window ({
                title: 'Password', width: 240, closeAction: 'hide',
                items: new Ext.Panel ({
                    bodyStyle: {'padding-top': '5px'},
                    layout: 'form', labelWidth: 80, labelAlign: 'right',
                    items: [{
                        fieldLabel: 'Password',  xtype: 'textfield', id: 'password1', width: 120, inputType: 'password',
                        listeners: {
                            specialkey: function (field, e) {
                                if (e.getKey () == Ext.EventObject.ENTER) {
                                    Ext.ComponentMgr.get ('password2').focus ();
                                }
                            }
                        }
                    },{
                        fieldLabel: 'Confirm',  xtype: 'textfield', id: 'password2', width: 120, inputType: 'password',
                        listeners: {
                            specialkey: function (field, e) {
                                if (e.getKey () == Ext.EventObject.ENTER) {
                                    savePassword (password_window.record);
                                }
                            }
                        }
                    }],
                    buttons: [
                        {
                            text: 'Save', iconCls:'save',
                            listeners: {
                                'click': function () {
                                    savePassword (password_window.record)
                                }
                            }
                        },{
                            text: 'Cancel', iconCls:'cancel',
                            handler: function () {
                                password_window.setVisible (false);
                            }
                        }
                    ]
                })
            })
        }
        Ext.ComponentMgr.get ('password1').setValue ('');
        Ext.ComponentMgr.get ('password2').setValue ('');
        password_window.record = r;
        password_window.setTitle ('Set Password - ' + r.data.name);
        password_window.setVisible (true);
    };

    function savePassword (r) {
        var password1 = Ext.ComponentMgr.get ('password1').getValue ();
        var password2 = Ext.ComponentMgr.get ('password2').getValue ();
        if (password1 != password2) {
            alert ('Passwords do not match.');
        }

        var params = { username: r.data.name, password: password1 };

        Ext.Ajax.request({
            url: jarvisUrl ('SetPassword'),
            params: params,

            // We received a response back from the server, that's a good start.
            success: function (response, request_options) {
                if (response.responseText == 'Success') {
                    password_window.setVisible (false);
                    r.data.has_password = password1 ? 'YES' : 'NO';
                    user_store.fireEvent("update", user_store, r, Ext.data.Record.EDIT);

                } else {
                    alert ('Set password declined: ' + response.responseText);
                }
            },
            failure: function (response, request_options) {
                alert ('Set password error: ' + response.responseText);
            }
        });
    };

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
    helpInit ('users', 'Demo: Users - Help');

    // Check for unsaved changes on all links.
    for (var i = 0; i < document.links.length; i++) {
        if (document.links[i].href.match (/#$/)) continue;
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
        var saved = exists && selectedRecord.get('id');

        Ext.ComponentMgr.get ('delete').setDisabled (! exists);
        Ext.ComponentMgr.get ('password').setDisabled (! saved);
        Ext.ComponentMgr.get ('save').setDisabled (! haveModifiedRecords);
    }

    user_store.load();
});
