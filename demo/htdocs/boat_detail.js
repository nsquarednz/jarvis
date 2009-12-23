Ext.onReady (function () {
    jarvisInit ('demo');

    var boat_id = jarvisHashArg (document.URL, 'id', '');
    if (boat_id <= 0) {
        alert ('Missing/Invalid boat_detail ID in URL.');
        return;
    }

    var tab_index = jarvisHashArg (document.URL, 'tab', 0);

    // create the main Data Store for the links
    var boat_detail_store = new Ext.data.JsonStore ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('boat_detail'), method: 'GET' }),
        root: 'data',
        idProperty: 'id',
        fields: ['id', 'class', 'name', 'registration_num', 'owner', 'description' ],
        pruneModifiedRecords: true,
        listeners: {
            'beforeload': function () {
                tabs.setDisabled (true);
            },
            'load': function () {
                r = boat_detail_store.getAt (0);
                if (r == null || (r.get ('id') != boat_id) || (boat_detail_store.getCount() != 1)) {
                    alert ('Data query failed for ID ' + boat_id + '.');
                    return;
                }
                tabs.setDisabled (false);
                document.getElementById ("boat_name").innerHTML = 'Edit details for boat: "' + r.get('name') + '" (' + r.get('id') + ')';
                summary_panel.findById ('class').setValue (r.get('class'));
                summary_panel.findById ('name').setValue (r.get('name'));
                summary_panel.findById ('registration_num').setValue (r.get('registration_num'));
                summary_panel.findById ('owner').setValue (r.get('owner'));
                description_panel.findById ('description').setValue (r.get('description'));

                setButtons ();
            },
            'loadexception': jarvisLoadException,
            'write' : function (store, record) {
                tabs.setDisabled (true);
                tabs.buttons[1].getEl().innerHTML = '&nbsp;<b>UPDATING...</b>';
                jarvisSendChange ('update', store, 'boat_detail', record);
            },
            'writeback' : function (store, result, ttype, record, remain) {
                remain || (tabs.buttons[1].getEl().innerHTML = '&nbsp');
                remain || tabs.setDisabled (false);
                store.handleWriteback (result, ttype, record, remain);
                setButtons ();
            }
        }
    });

    var summary_panel = new Ext.Panel({
        labelWidth: 130,
        layout: 'form',
        title: 'Summary',
        bodyStyle:'padding:15px',
        labelPad: 10,
        labelAlign: 'right',
        defaultType: 'textfield',
        defaults: {             // Defaults for contained items.
            width: 400,
            msgTarget: 'side'
        },
        layoutConfig: {
            labelSeparator: ''
        },
        items: [{
                fieldLabel: 'Class',
                id: 'class',
                name: 'class',
                disabled: true
            },{
                fieldLabel: 'Name',
                id: 'name',
                name: 'name',
                listeners: { 'change': function () { boat_detail_store.getAt (0).set ('name', this.getValue ()); setButtons() } }
            },{
                fieldLabel: 'Reg #',
                id: 'registration_num',
                name: 'registration_num',
                listeners: { 'change': function () { boat_detail_store.getAt (0).set ('registration_num', this.getValue ()); setButtons() } }
            },{
                fieldLabel: 'Owner',
                id: 'owner',
                name: 'owner',
                listeners: { 'change': function () { boat_detail_store.getAt (0).set ('owner', this.getValue ()); setButtons() } }
            }
        ],
    });

    var description_panel = new Ext.Panel({
        labelWidth: 130,
        layout: 'form',
        title: 'Description',
        bodyStyle:'padding:15px',
        labelPad: 10,
        defaultType: 'textarea',
        defaults: { width: 600, height: 300, msgTarget: 'side' },
        layoutConfig: { labelSeparator: '' },
        items: [{
            fieldLabel: '<b>Description</b><br><br>Multiparagraph text, included in glossy pamphlets each month.',
            id: 'description',
            name: 'description',
            listeners: { 'change': function () { boat_detail_store.getAt (0).set ('description', this.getValue ()); setButtons() } }
        }],
    });

    var tabs = new Ext.TabPanel({
        renderTo: 'extjs',
        disabled: true,
        autoHeight: false,
        deferredRender: false,          // Resolves bug which means first tab doesn't render.
        activeTab: tab_index,
        height: 400,
        items: [ summary_panel, description_panel ],
        buttons: [
            { text: 'Help', iconCls:'help', handler: function () { helpShow (); } },
            new Ext.Toolbar.Fill (),
            {
                text: 'Boats', iconCls:'prev',
                handler: function () {
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    location.href = 'boat.html';
                }
            }, {
                text: 'Save Changes', id: 'save',
                iconCls:'save',
                handler: function () {
                    boat_detail_store.writeChanges ();
                }
            }, {
                text: 'Reload', id: 'reload',
                iconCls:'reload',
                handler: function () {
                    if (haveChanges () && ! confirm ("Really discard unsaved changes?")) return;
                    boat_detail_store.reload ();
                }
            }
        ]
    });

    //-------------------------------------------------------------------------
    // HAVE CHANGES FUNCTION
    //-------------------------------------------------------------------------
    function haveChanges () {
        return (boat_detail_store.getModifiedRecords().length > 0);
    }

    //-------------------------------------------------------------------------
    // SET BUTTONS FUNCTION
    //-------------------------------------------------------------------------
    // Button dis/enable controls.
    function setButtons () {
        var haveModifiedRecords = haveChanges ();

        Ext.ComponentMgr.get ('save').setDisabled (! haveModifiedRecords);
    }

    //-------------------------------------------------------------------------
    // MAIN PROGRAM
    //-------------------------------------------------------------------------
    // Load our help system.
    helpInit ('boat_detail', 'Demo: Boat Detail - Help');

    // Check for unsaved changes on all links.
    for (var i = 0; i < document.links.length; i++) {
        document.links[i].onclick = function () {
            return (! haveChanges () || confirm ("Really discard unsaved changes?"));
        }
    }

    // Take our standard Jarvis POST params, and add our "id" param for the load.
    var params = {};
    params.id = boat_id;
    boat_detail_store.load ({'params': params});
});