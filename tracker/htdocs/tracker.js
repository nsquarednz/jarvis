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

Ext.ns('jarvis.tracker');

Ext.BLANK_IMAGE_URL = '/ext-2.3/resources/images/default/s.gif';

/**
 * The main UI Tab that new tabs are added to.
 */
jarvis.tracker.informationTabPanel = null;

/**
 * This map holds functions that are loaded from external files. These functions
 * create the tabs of data - e.g. the 'queries' type tab that details a specific
 * query.
 */
jarvis.tracker.trackerSubpages = {};

/**
 * This is a list of all the tabs shown onscreen to the user, allowing the code
 * to switch to a tab if the user's already got it open, rather than create a
 * whole new one.
 *
 * The key is the 'id' of the tab - the path to the tab as per the application
 * browser shown on the left of the UI in the application.
 */
jarvis.tracker.trackerTabs = {};

/**
 * Global default configuration for the Jarvis Tracker application.
 */
jarvis.tracker.configuration = {
    defaultDateRange: new jarvis.Timeframe ('..now')
};

/**
 * A static/global function for loading a new page type whose code will be
 * able to create a new tab of a specific type.
 *
 * The JavaScript file, when loaded and evaluated is expected to return a
 * function with the following signature:
 *
 *     function (appName, extra);
 *
 * And this function is supposed to return an ExtJS Component that can
 * become a tab in an ExtJS TabPanel.
 *
 * 'extra' above is tab type specific, and is built up and passed by other
 * code (see loadAndShowTab).
 *
 * The returned Panel object is also able to respond to an 'updateparameters'
 * event, which is fired in various panel specific cases (mostly when the user
 * does something that would trigger the reload of that specific tab).
 *
 * Parameters:
 *      page - the page type, which is also the filename of JavaScript to
 *             load.
 *      callback - the function to call after the page is loaded, if any.
 */
jarvis.tracker.loadExternalPage = function(page, callback) {
    Ext.Ajax.request ({
        url: page,
        success: function (xhr) {
            var t = eval(xhr.responseText);
            jarvis.tracker.trackerSubpages[page] = t;
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
};

/**
 * A static/global function for showing a new tab for a specific selection
 * made by the user.
 *
 * Parameters:
 *      id - The id (node) as per the application browser. Refer to 
 *           loadAndShowTabFromPath for details on the form this id can take.
 *
 *      page - the page type, which is also the filename of JavaScript to
 *             load.
 *
 *      appName - the application name. Should be the same as what is
 *                in the 'id'.
 *
 *      extraParameters - any extra parameters to pass to the tab when loaded.
 *
 *      callback - the function to call after tab is created, if any.
 */
jarvis.tracker.loadAndShowTab = function(id, page, appName, extraParameters, callback) {
    if (!jarvis.tracker.trackerSubpages[page]) {
        jarvis.tracker.loadExternalPage(page, function (p) { 
            jarvis.tracker.loadAndShowTab (id, page, appName, extraParameters, callback); 
        });
    } else {
        if (jarvis.tracker.trackerTabs[id]) {
            if (extraParameters) {
                jarvis.tracker.trackerTabs[id].fireEvent ('updateparameters', extraParameters);
            }
            jarvis.tracker.informationTabPanel.setActiveTab (jarvis.tracker.trackerTabs[id]);
        } else {
            extraParameters = extraParameters || {};
            extraParameters.url = id;
            var t = jarvis.tracker.trackerSubpages[page](appName, extraParameters);
            t.on (
                'destroy', function () { jarvis.tracker.trackerTabs[id] = null }
            );
            jarvis.tracker.informationTabPanel.add (t);
            jarvis.tracker.informationTabPanel.setActiveTab (t);
            jarvis.tracker.trackerTabs[id] = t;

            if (callback) {
                callback(t);
            }
        }
    };
};

/**
 * This function will parse a path and then call loadAndShowTab with the right
 * information, based on the path provide.
 *
 * path is to be one of the following forms:
 *
 * root         - for the root summary node
 * <app name>   - for the summary of an application
 * <app name>/[Errors|Datasets|Users|Events]
 *              - for summary of an area of an application
 * <app name>/Errors?date=<julian date>&id=<error id>
 *              - for a specific error. The Errors tab will then show that error
 *                already selected.
 * <app name>/Datasets/<dataset path>
 *              - for details on a dataset (<dataset path> may include backslashes)
 * <app name>/Datasets/<dataset path>?<parameters>
 *              - for details on a dataset (<dataset path> may include backslashes)
 *              - <parameters> are passed through to the relevant dataset detail page
 *                and be used for the query parameters there.
 * <app name>/Events?<parameters>
 *              - for details on events that have occurred based on the parameters.
 *              - <parameters> are passed through to the event explorer page.
 * <app name>/Users/<user name>
 *
 * Note - not all paths do anything yet
 */
jarvis.tracker.loadAndShowTabFromPath = function(path, callback) {
    var pathAndParam = path.split('?');
    var parts = pathAndParam[0].split('/');
    var params = null;

    if (pathAndParam.length > 1) {
        params = Ext.urlDecode (pathAndParam[1]);
    }

    // Root node has only one part.
    if (path == 'root') {
        jarvis.tracker.loadAndShowTab (pathAndParam[0], 'summary.js', null, null, callback);
    }
    // If the length is 1, it must be an application name.
    else if (parts.length == 1) {
        jarvis.tracker.loadAndShowTab (pathAndParam[0], 'application-summary.js', parts[0], null, callback);
    }
    // If there are two parts - the second part will be Errors/Datasets etc.
    else if (parts.length == 2) {
        var extra = params ? {
            params: params
        } : null;

        if (parts[1] == 'Errors') {
            jarvis.tracker.loadAndShowTab (pathAndParam[0], 'errors-summary.js', parts[0], extra, callback);
        } else if (parts[1] == 'Datasets') {
            jarvis.tracker.loadAndShowTab (pathAndParam[0], 'queries-summary.js', parts[0], extra, callback);
        } else if (parts[1] == 'Users') {
            jarvis.tracker.loadAndShowTab (pathAndParam[0], 'users-summary.js', parts[0], extra, callback);
        } else if (parts[1] == 'Events') {

            // The event explorer is special - each time we load one, we create a unique instance
            jarvis.tracker.loadAndShowTabFromPath.nextEventExplorerNumber = jarvis.tracker.loadAndShowTabFromPath.nextEventExplorerNumber || 0;
            jarvis.tracker.loadAndShowTabFromPath.nextEventExplorerNumber++;

            extra = extra || {
                params: {}
            };
            extra.eventExplorerNumber = jarvis.tracker.loadAndShowTabFromPath.nextEventExplorerNumber;
            extra.params.appName = extra.params.appName || parts[0];

            jarvis.tracker.loadAndShowTab (pathAndParam[0] + '/' + extra.eventExplorerNumber, 'event-explorer.js', parts[0], extra, callback);
        }
    }

    // If there are more than two parts, then look at what details we're after
    
    // Datasets.
    // Before showing the dataset page, we need to know what sort of dataset
    // we're dealing with - this will allow the query tab to better show
    // relevant data.
    //
    // We could do this in the query code, but ExtJS panels require their regions
    // to be defined pre-render, and it is easier to do this query here,
    // and pass the information through to the query page.
    else if (parts.length >= 3 && parts[1] == 'Datasets') {

        var app = parts[0];
        parts.splice(0, 2);
        
        Ext.Ajax.request ({
            url: jarvisUrl ('dataset-info/' + app + '/' + parts.join('/')),
            method: 'GET',
            success: function (xhr, req) { 
                var datasetInfo = Ext.util.JSON.decode (xhr.responseText);
                jarvis.tracker.loadAndShowTab (pathAndParam[0], 'query.js', app, {
                    query: parts.join ('/'),
                    params: params,
                    datasetInfo: datasetInfo
                }, callback);
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        });
    }

    // User information.
    else if (parts.length >= 3 && parts[1] == 'Users') {
        jarvis.tracker.loadAndShowTab (pathAndParam[0], 'user.js', parts[0], {
            user: parts[2]
        }, callback);
    }
};

//
// Main code to build the screen. 
//
Ext.onReady (function () {
    Ext.Ajax.on ('requestexception', function (conn, response, options) {
        if (response.status == 401) { // 401 == unauthorized and means we should try and log in.
            jarvis.tracker.login (options);
        } 
    });

    jarvisInit ('tracker'); // Tells the codebase what our Jarvis application name is, and the login function.
    Ext.QuickTips.init();

    // This global store lists all the applications
    // available in the database - get it once as it's a
    // thing that doesn't really rely on specific tab details.
    jarvis.tracker.applicationsInDatabase = new Ext.data.Store ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('applications_in_database'), method: 'GET' }),
        autoLoad: true,
        reader: new Ext.data.JsonReader ({
            root: 'data',
            id: 'app_name',
            totalProperty: 'fetched',
            fields: ['app_name']
        }),
        listeners: {
            'loadexception': jarvis.tracker.extStoreLoadExceptionHandler,
        }
    });

    // The UI
    var logoutButtonId = Ext.id();
    
    var titleBar = {
        xtype: 'panel',
        layout: 'absolute',
        region: 'north',
        height: 45,
        items: [
            {
                xtype: 'container',
                autoEl: {
                    html: '<h1>The Jarvis Tracker</h1><div class="logout-button" id="' + logoutButtonId + '">logout</div>',
                    tag: 'div'
                },
                anchor: '100% 100%',
                cls: 'title-bar'
            },
        ]
    };

    // Tree - showing the list of jarvis applications and suchlike.
    var treePanel = new Ext.tree.TreePanel ({
        title: 'Application Browser',
        region: 'west',
        split: true,
        width: 250,
        loader: new Ext.tree.TreeLoader({
            url: jarvisUrl('list'),
            preloadChildren: true,
            requestMethod: 'GET'
        }),
        collapsible: true,
        autoScroll: true,
        root: new Ext.tree.AsyncTreeNode ({
            text: 'Applications',
            expanded: true,
            id: 'root'
        }),
        listeners: {
            click: function (node, event) { 

                // Load a path only if it's a leaf, or a special non-leaf node that
                // we know has a summary.
                var parts = node.id.split('/');

                // avoid loading a tab for directories within 'Datasets'
                if (node.leaf == 1 || parts.length < 3) { // node.isLeaf() does not work in ExtJS v2.3
                    jarvis.tracker.loadAndShowTabFromPath (node.id);
                }
            }
        }
    });
    
        
    jarvis.tracker.informationTabPanel = new Ext.TabPanel ({
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
        layoutOnTabChange:true
    });

    // Main layout holder
    var mainContainer = new Ext.Panel ({
        layout: 'border',
        items: [
            titleBar,
            treePanel,
            jarvis.tracker.informationTabPanel
        ]
    });

    var viewport = new Ext.Viewport({
        layout:'fit',        
        items:[ 
                mainContainer
        ]       
    });

    Ext.get (logoutButtonId).on ('click', function () {
        Ext.Ajax.request ({
            url: jarvisUrl ('__logout'),
            method: 'GET',
            success: function (xhr) { 
                jarvis.tracker.login (function () {});
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        })
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
    jarvis.tracker.loadAndShowTabFromPath ('root', function () { viewport.doLayout(false); });
});


