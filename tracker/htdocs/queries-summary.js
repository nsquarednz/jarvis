/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides an Ext Container for a summary page for queries made for an 
 *              application.
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

    // The timeframe to profile for.
    var profileTimeframe = new jarvis.Timeframe ('2...now');

    // The profile data
    var queryProfilesStore = new Ext.data.JsonStore ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('queries_profile/' + appName), method: 'GET' }),
        autoLoad: true,
        root: 'data',
        fields: ['dataset', 'action', 'total_duration_ms_percentage', 'total_requests_percentage', 'number_of_requests', 'total_duration_ms', 'avg_duration_ms', 'max_duration_ms', 'min_duration_ms', 'avg_nrows'],
        baseParams: {
            from: profileTimeframe.from().formatForServer(),
            to: profileTimeframe.to().formatForServer()
        },
        listeners: {
            'load': function (records) {
                var totalTimeSpent = 0;
                var totalRequestsMade = 0;
                records.each (function (d) {
                    totalTimeSpent += d.get('total_duration_ms') * 1;
                    totalRequestsMade += d.get('number_of_requests') * 1;
                });
                records.each (function (d) {
                    d.set ('total_duration_ms_percentage', (d.get('total_duration_ms') * 1) / totalTimeSpent);
                    d.set ('total_requests_percentage', (d.get('number_of_requests') * 1) / totalRequestsMade);
                });
            },
            'loadexception': jarvis.tracker.extStoreLoadExceptionHandler
        }
    });

    var queryProfiles = new Ext.grid.GridPanel({
        store: queryProfilesStore,
        title: 'Query Profile Results',
        region: 'north', 
        height: 300,
        columns: [
            {
                header: 'Dataset',
                dataIndex: 'dataset',
                sortable: true
            },
            {
                header: 'Time Spent (%)',
                dataIndex: 'total_duration_ms_percentage',
                sortable: true,
                renderer: function (x) { return (Math.round (x * 10000) / 100) + '%'; }
            },
            {
                header: 'Req. (%)',
                dataIndex: 'total_requests_percentage',
                sortable: true,
                renderer: function (x) { return (Math.round (x * 10000) / 100) + '%'; }
            },
            {
                header: 'Total Req.',
                dataIndex: 'number_of_requests',
                sortable: true,
                renderer: function (x) { return Math.round (x); }
            },
            {
                header: 'Time Spent (ms)',
                dataIndex: 'total_duration_ms',
                sortable: true
            },
            {
                header: 'Avg. Time Spent (ms)',
                dataIndex: 'avg_duration_ms',
                sortable: true,
                renderer: function (x) { return Math.round (x); }
            },
            {
                header: 'Min Time Spent (ms)',
                dataIndex: 'min_duration_ms',
                sortable: true
            },
            {
                header: 'Max Time Spent (ms)',
                dataIndex: 'max_duration_ms',
                sortable: true
            },
            {
                header: 'Avg. # of Rows',
                dataIndex: 'avg_nrows',
                sortable: true,
                renderer: function (x) { return Math.round (x); }
            }
        ],
        viewConfig: {
            forceFit: true
        },
        sm: new Ext.grid.RowSelectionModel({singleSelect:true})
    });


    return new Ext.Panel ({
        title: appName + '- Queries',
        layout: 'border',
        hideMode: 'offsets',
        closable: true,
        items: [
            queryProfiles,
            {
                xtype: 'TimeBasedVisualisation',
                region: 'center',
                dataSource: {
                    dataset: 'tps/' + appName,
                },
                graph: new jarvis.graph.TpsGraph(),
                graphConfig: {
                    timeframe: jarvis.tracker.configuration.defaultDateRange.clone()
                }
            }
        ]
    });

}; })();

