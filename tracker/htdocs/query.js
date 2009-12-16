/**
 * The main page for looking at queries made via Jarvis.
 */
Ext.onReady (function () {
    jarvisInit ('tracker');
    
    var titleBar = {
        region: 'north',
        xtype: 'container',
        autoEl: {
            html: "<h1>The Jarvis Tracker</h1>",
            tag: 'div'
        },
        height: 45,
        cls: "title-bar"
    };

    // Tree - showing the list of jarvis applications and suchlike.
    var treePanel = new Ext.tree.TreePanel ({
        title: "Application Browser",
        region: "west",
        split: true,
        width: 400,
        loader: new Ext.tree.TreeLoader({
            url: jarvisUrl('list'),
            requestMethod: 'GET',
            listeners: {
                loadexception: jarvisLoadException
            }
        }),
        collapsible: true,
        autoScroll: true,
        root: new Ext.tree.AsyncTreeNode ({
            text: "Applications",
            expanded: true,
            id: 'root',
        }),
        tools: [{
            id: 'search'
        }]
    });
    
    var informationTabPanel = new Ext.TabPanel ({
        autoScroll: true,
        deferredRender: false,
        items: [ 
        ]
    });

    var centerPanel = new Ext.Panel({
        region:'center',
        layout:'fit',
        border:false,
        items: [
            informationTabPanel
        ]
    });

    var status = new Ext.StatusBar ({
        id: 'status-bar',
        defaultText: 'hello world',
        region: 'south'
    });

    // Main layout holder
    var mainContainer = new Ext.Panel ({
        layout: 'border',
        items: [
            titleBar,
            treePanel,
            centerPanel,
            status
        ]
    });

    viewport = new Ext.Viewport({
        layout:'fit',        
        items:[ 
                mainContainer
        ]       
    });


    /** 
     * Start off with summary details as a tab
     */
    Ext.Ajax.request ({
        url: "summary.js",
        success: function (xhr) {
            var t = eval(xhr.responseText);
            informationTabPanel.add (t);
            informationTabPanel.setActiveTab (t);
        },
        failure: function () {
            Ext.Msg.alert ("Cannot load summary.js");
        }
    });
});


