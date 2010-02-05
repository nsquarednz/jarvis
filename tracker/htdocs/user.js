/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides an Ext Container for detailing a user's use of the system.
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

(function () {

/**
 * The user login details includes addresses from which the user has logged in.
 * We do a reverse DNS lookup on these addresses so it's a bit easier to see
 * where they're based.
 *
 * We store a global list here of all IP addresses retrieved, so we don't constantly
 * retrieve the same ones.
 *
 * Map is ipaddress -> server name.
 */
var ReverseDnsCache = function () {
    this.addEvents({
        'updated': true
    });
};
ReverseDnsCache = Ext.extend (ReverseDnsCache, Ext.util.Observable);
var globalReverseDnsCache = new ReverseDnsCache;

/**
 * The actual function that builds the tab UI.
 */
return function (appName, extra) {

    var user = extra.user;

    var loginsStore = new Ext.data.Store ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('user_logins/' + appName + '/' + user), method: 'GET' }),
        autoLoad: true,
        reader: new Ext.data.JsonReader ({
            root: 'data',
            id: 'id',
            totalProperty: 'fetched',
            fields: ['sid', 'logged_in', 'error_string', 'group_list', 'address', 'start_time']
        }),
        listeners: {
            load: function (records) {
                var ipAddressesToLookup = {};
                records.each (function (r) {
                    var a = r.get ('address');
                    if (!globalReverseDnsCache[a]) {
                        ipAddressesToLookup[a] = 1;
                    }
                });

                ipAddressesToLookup = pv.keys (ipAddressesToLookup);
                if (ipAddressesToLookup.length > 0) {
                    Ext.Ajax.request ({
                        url: jarvisUrl ('reverse-dns-lookup'),
                        method: 'GET',
                        params: {
                            ip_address: ipAddressesToLookup
                        },
                        success: function (xhr) {
                            try {
                                var resp = Ext.util.JSON.decode (xhr.responseText); 
                                pv.keys(resp.data).forEach (function (x) {
                                    globalReverseDnsCache[x] = resp.data[x];
                                });

                                globalReverseDnsCache.fireEvent('updated');

                            } catch (error) {
                                Ext.Msg.show ({
                                    title: 'Reverse DNS Lookup Error',
                                    msg: 'Cannot read reverse DNS information: ' + error,
                                    buttons: Ext.Msg.OK,
                                    icon: Ext.Msg.ERROR
                               });
                            }
                        },
                        failure: jarvis.tracker.extAjaxRequestFailureHandler
                    });
                }
            },
            loadexception: jarvis.tracker.extStoreLoadExceptionHandler
        }
    });

    var logins = new Ext.grid.GridPanel({
        width: '40%',
        anchor: '100% 50%',
        title: 'User Logins',
        split: true,
        store: loginsStore,
        columns: [
            {
                header: 'Time',
                dataIndex: 'start_time',
                sortable: true,
                width: 30,
                renderer: function(x) { return Date.fromJulian(x).format ('d/m H:i:s'); }
            },
            {
                header: 'Address',
                dataIndex: 'address',
                width: 20,
                renderer: function (x, c) { 
                    if (globalReverseDnsCache[x] && globalReverseDnsCache[x] != x) {
                        c.attr = 'ext:qtip="' + x + '"';
                        return globalReverseDnsCache[x];
                    }
                    return x;
                }
            },
            {
                header: 'SID',
                dataIndex: 'sid',
                width: 40
            },
            {
                header: 'Success?',
                dataIndex: 'logged_in',
                width: 15,
                renderer: function (x) { return x == 1 ? 'yes' : 'no' }
            },
            {
                header: 'Error',
                dataIndex: 'error_string',
                width: 40,
                hidden: true
            },
            {
                header: 'Groups',
                dataIndex: 'group_list',
                width: 40,
                hidden: true
            }
        ],
        viewConfig: {
            forceFit: true
        },
        sm: new Ext.grid.RowSelectionModel({
            singleSelect:true
        }),
        listeners: {
            rowdblclick: function (g, i) {
                var record = g.store.getAt (i);
                var path = appName + '/Events?sid=' + record.get ('sid');
                jarvis.tracker.loadAndShowTabFromPath (path);
            }
        }
    });

    var errorList = new Ext.ux.ErrorList ({
        region: 'east',
        width: '40%',
        split: true,
        title: 'Recent Errors for ' + appName,
        anchor: '100% 50%',
        dataSourceParams: {
            limit: true,
            user: user,
            appName: appName
        }
    });

    globalReverseDnsCache.on ('updated', function () {
        loginsStore.fireEvent('datachanged'); // Force the grid to re-render to get the new address information.
    });

    var sidePanel = new Ext.Panel({
        layout: 'anchor',
        title: 'User Details',
        width: '40%',
        split: true,
        region: 'east',
        collapsible: true,
        items: [
            logins,
            errorList
        ]
    });

    return new Ext.Panel ({
        title: appName + ' - Users - ' + user,
        layout: 'border',
        hideMode: 'offsets',
        closable: true,
        items: [
            {
                xtype: 'TimeBasedVisualisation',
                region: 'center',
                dataSource: {
                    dataset: 'tps/' + appName,
                    params: {
                        user: user
                    }
                },
                graph: new jarvis.graph.TpsGraph(),
                graphConfig: {
                    timeframe: jarvis.tracker.configuration.defaultDateRange.clone()
                }
            },
            sidePanel
        ]
    });

}; })();

