/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides a summary page, summarising a specific Jarvis application.
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
return function (appName, extra) {

    var recentErrorsStore = new Ext.data.Store ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('recent_errors/' + appName), method: 'GET' }),
        autoLoad: true,
        reader: new Ext.data.JsonReader ({
            root: 'data',
            id: 'id',
            totalProperty: 'fetched',
            fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'message']
        }),
        listeners: {
            'loadexception': jarvis.tracker.extStoreLoadExceptionHandler
        }
    });

    var recentErrorsList = new Ext.grid.GridPanel({
        store: recentErrorsStore,
        title: 'Recent Errors: ' + appName,
        columns: [
            {
                header: 'Event Time',
                dataIndex: 'start_time',
                sortable: true,
                width: 50,
                renderer: function(x) { return Date.parseDate(x, 'c').format ('D jS M Y H:i:s'); }
            },
            {
                header: 'User',
                dataIndex: 'username',
                width: 20,
                sortable: true
            },
            {
                header: 'Error',
                dataIndex: 'message',
                sortable: false,
                renderer: function (x) { return Ext.util.Format.ellipsis (x, 60); }
            }
        ],
        viewConfig: {
            forceFit: true
        },
        listeners: {
            rowdblclick: function (g, i) {
                var record = g.store.getAt (i);
                var path = record.get('app_name') + '/Errors?date=' + record.get ('start_time') + '&id=' + record.id;
                jarvis.tracker.loadAndShowTabFromPath (path);
            }
        },
        sm: new Ext.grid.RowSelectionModel({singleSelect:true})
    });

    var eastAccordion = new Ext.Panel({
        region: 'east',
        layout: 'accordion',
        split: true,
        collapsible: true,
        width: 600,
        title: 'Recently',
        items: [
            recentErrorsList
        ]
    });

    var tps = {
        xtype: 'TimeBasedVisualisation',
        region: 'center',
        dataSource: {
            dataset: 'tps/'+ appName
        },
        graph: new jarvis.graph.TpsGraph(),
        graphConfig: {
            timeframe: jarvis.tracker.configuration.defaultDateRange.clone()
        }
    };

    return new Ext.Panel ({
        title: appName,
        closable: true,
        layout: 'border',
        hideMode: 'offsets',
        items: [
            eastAccordion,
            tps
        ]
    });

}; })();

