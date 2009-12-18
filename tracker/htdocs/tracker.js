
/**
 * The main page for looking at queries made via Jarvis.
 */

// Adds a tab to the page

var informationTabPanel = null;

var trackerSubpages = {};
var trackerTabs = {};

function loadExternalPage (page, callback) {
    Ext.Ajax.request ({
        url: page,
        success: function (xhr) {
            var t = eval(xhr.responseText);
            trackerSubpages[page] = t;
            if (callback)
                callback();
        },
        failure: function () {
            Ext.Msg.alert ("Cannot load: " + page);
        }
    });
}

function addTab (id, page, appName, extraParameters) {
    if (!trackerSubpages[page]) {
        loadExternalPage(page, function (p) { addTab (id, page, appName, extraParameters); });
    } else {
        if (trackerTabs[id]) {
            informationTabPanel.setActiveTab (trackerTabs[id]);
        } else {
            var t = trackerSubpages[page](appName, extraParameters);
            t.on (
                'destroy', function () { trackerTabs[id] = null }
            );
            informationTabPanel.add (t);
            informationTabPanel.setActiveTab (t);
            trackerTabs[id] = t;
        }
    };
}

// Main code to build the screen
Ext.onReady (function () {
    prettyPrint();
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
        }],
        listeners: {
            click: function (node, event) { 
                console.log(node, event);
                var parts = node.id.split("/");

                // Capture clicking on the level below the application.
                if (parts.length == 2) {
                    if (parts[1] == "errors") {
                        addTab (node.id, "errors-summary.js", parts[0]);
                    }
                }

                // Capture clicking on a specific item within 'queries', 'users' etc.
                if (node.leaf == 1 && parts.length >= 3) { // TODO - node.isLeaf() does not work
                    if (parts[1] == "queries") {
                        var app = parts[0];
                        parts.splice(0, 2);
                        addTab (node.id, "query.js", app, {
                            query: parts.join ("/")
                        });
                    }
                }
            }
        }
    });
    
    informationTabPanel = new Ext.TabPanel ({
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

    // Main layout holder
    var mainContainer = new Ext.Panel ({
        layout: 'border',
        items: [
            titleBar,
            treePanel,
            centerPanel
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
    addTab ("summary", "summary.js");
});


