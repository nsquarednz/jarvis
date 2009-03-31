Ext.onReady (function () {
    jarvisInit ('demo');

    var url = document.URL;
    var args = Ext.urlDecode (url.substring(url.indexOf('?')+1, url.length));
    var boat_id = args.id || 0;
    if (boat_id <= 0) {
        alert ('Missing/Invalid boat_detail ID in URL.');
        return;
    }

    var tab_index = args.tab || 0;

    // create the main Data Store for the links
    var boat_detail_store = new Ext.data.JsonStore ({
        url: jarvisPostUrl (),      // We need to give extra params, so will use POST.
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
                document.getElementById ("boat_name").innerHTML = 'Edit details for: "' + r.get('name') + '" (' + r.get('id') + ')';
                summary_panel.findById ('class').setValue (r.get('class'));
                summary_panel.findById ('name').setValue (r.get('name'));
                summary_panel.findById ('registration_num').setValue (r.get('registration_num'));
                summary_panel.findById ('owner').setValue (r.get('owner'));
                description_panel.findById ('description').setValue (r.get('description'));

                setButtons ();
                loadMugshot ();
            },
            'loadexception': jarvisLoadException,
            'update' : function (store, record, operation) {
                if (operation == Ext.data.Record.COMMIT) {
                    tabs.setDisabled (true);
                    jarvisUpdate (store, 'boat_detail', record);
                }
                setButtons ();
            },
            'writeback' : function (store, result) {
                tabs.setDisabled (false);
                if (result.success != 1) {
                    store.reload ();
                    alert (result.message);
                }
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
        title: 'Introduction',
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
        renderTo: 'boat_detail_panel',
        disabled: true,
        autoHeight: false,
        deferredRender: false,          // Resolves bug which means first tab doesn't render.
        activeTab: tab_index,
        height: 400,
        items: [ summary_panel, description_panel ],
        buttons: [
            {
                text: 'Save Changes',
                iconCls:'save',
                handler: function () {
                    boat_detail_store.commitChanges ();
                }
            },
            {
                text: 'Discard & Reload',
                iconCls:'remove',
                handler: function () {
                    boat_detail_store.reload ();
                }
            }
        ]
    });

    // Button dis/enable controls.
    function setButtons () {
        var haveModifiedRecords = (boat_detail_store.getModifiedRecords().length > 0);

        if (haveModifiedRecords) {
            tabs.buttons[0].enable ();
            tabs.buttons[1].enable ();
        } else {
            tabs.buttons[0].disable ();
            tabs.buttons[1].disable ();
        }
    }

    // Take our standard Jarvis POST params, and add our "id" param for the load.
    var params = new jarvisPostParams ('fetch', 'boat_detail')
    params.id = boat_id;
    boat_detail_store.load ({'params': params});
});