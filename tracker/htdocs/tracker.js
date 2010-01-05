/**
 * Description: This ExtJS code builds the main page for accessing/viewing data
 *              available to the Jarvis Tracker, both in the tracker database
 *              and in the Jarvis configuration on the system.
 *
 * Licence:
 *       This file is part of the Jarvis Tracker application.
 *
 *       Jarvis is free software: you can redistribute it and/or modify
 *       it under the terms of the GNU General Public License as published by
 *       the Free Software Foundation, either version 3 of the License, or
 *       (at your option) any later version.
 *
 *       Jarvis is distributed in the hope that it will be useful,
 *       but WITHOUT ANY WARRANTY; without even the implied warranty of
 *       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *       GNU General Public License for more details.
 *
 *       You should have received a copy of the GNU General Public License
 *       along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
 *
 *       This software is Copyright 2008 by Jamie Love.
 */

// TODO MOVE this function

/**
 * Function Description:   Returns the julian date value for the given date object,
 *                         adjusting to UTC from browser local time.
 */
Date.prototype.getJulian = function () {
    // 2440587.5 is the julian date offset for unix epoch
    // time. 
    return this.getTime() / (1000 * 60 * 60 * 24) + 2440587.5; 
}
Date.fromJulian = function (jt) {
    return new Date(Math.round((jt - 2440587.5) * (1000 * 60 * 60 * 24)));
}

// Adds a tab to the page

var informationTabPanel = null;

var trackerSubpages = {};
var trackerTabs = {};

var trackerConfiguration = {
    defaultDateRange: new jarvis.Timeframe ('..now')
};

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
            Ext.Msg.show ({
                title: 'Page Load Error',
                msg: 'Cannot load: ' + page,
                buttons: Ext.Msg.OK,
                icon: Ext.Msg.ERROR
           });
        }
    });
}

function addTab (id, page, appName, extraParameters, callback) {
    if (!trackerSubpages[page]) {
        loadExternalPage(page, function (p) { addTab (id, page, appName, extraParameters, callback); });
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

            //informationTabPanel.doLayout();

            if (callback) {
                callback(t);
            }
        }
    };
}

// Main code to build the screen
Ext.onReady (function () {
    jarvisInit ('tracker');
    
    var titleBar = {
        region: 'north',
        xtype: 'container',
        autoEl: {
            html: '<h1>The Jarvis Tracker</h1>',
            tag: 'div'
        },
        height: 45,
        cls: 'title-bar'
    };

    // Tree - showing the list of jarvis applications and suchlike.
    var treePanel = new Ext.tree.TreePanel ({
        title: 'Application Browser',
        region: 'west',
        split: true,
        width: 400,
        loader: new Ext.tree.TreeLoader({
            url: jarvisUrl('list'),
            preloadChildren: true,
            requestMethod: 'GET',
            listeners: {
                loadexception: jarvisLoadException
            }
        }),
        collapsible: true,
        autoScroll: true,
        root: new Ext.tree.AsyncTreeNode ({
            text: 'Applications',
            expanded: true,
            id: 'root',
        }),
        tools: [{
            id: 'search'
        }],
        listeners: {
            click: function (node, event) { 
                var parts = node.id.split('/');

                // Capture clicking on the level below the application.
                if (parts.length == 2) {
                    if (parts[1] == 'Errors') {
                        addTab (node.id, 'errors-summary.js', parts[0]);
                    } else if (parts[1] == 'Queries') {
                        addTab (node.id, 'queries-summary.js', parts[0]);
                    }
                }

                // Capture clicking on a specific item within 'queries', 'users' etc.
                if (node.leaf == 1 && parts.length >= 3) { // TODO - node.isLeaf() does not work
                    if (parts[1] == 'Queries') {
                        var app = parts[0];
                        parts.splice(0, 2);
                        addTab (node.id, 'query.js', app, {
                            query: parts.join ('/')
                        });
                    }
                }
            }
        }
    });
    
        
    informationTabPanel = new Ext.TabPanel ({
        region:'center',
        deferredRender: false,
        enableTabScroll: true,
        margins:'0 4 4 0',
        activeTab:0,

        // This layoutOnTabChange call forces the tab contents to be drawn right down
        // the component tree when tabs are added. Without this, I was finding that 
        // accordions within 
        // the tab would have their panel's drawn, but not the panel contents drawn 
        // (for multi-item contents - if an accordion panel's layout was 'fit', it'd
        // draw that fine for some reason).
        //
        // I investigated for about a day, and could only identify that while
        // the tab's accordion's panels were rendered, the doLayout() call was never
        // made to the panel, and so such panel's items would not be rendered.
        // It was possible to force the render by resizing the browser height, but
        // that's sub-optimal. Note that this affected only the initially visible 
        // accordion panel, not the other panels which are rendered afterward.
        //
        // Note that calling 'doLayout()' on the tab after it is added has the same
        // effect.
        layoutOnTabChange:true,
    });

    // Main layout holder
    var mainContainer = new Ext.Panel ({
        layout: 'border',
        items: [
            titleBar,
            treePanel,
            informationTabPanel
        ]
    });

    var viewport = new Ext.Viewport({
        layout:'fit',        
        items:[ 
                mainContainer
        ]       
    });


    /** 
     * Start off with summary details as a tab.
     *
     * Note that we force a relayout after the load as the informationTabPanel
     * does not have an initial tab, and because without an initial tab ExtJS appears
     * to have a bug which causes the tab height to be mis-calculated
     * by about 15 pixels, chopping off the bottom of the tab's contents
     * (until it is resized or layout is forced to recalculate)
     */
    addTab ('Applications', 'summary.js', null, null, function () { viewport.doLayout(false); });
});


