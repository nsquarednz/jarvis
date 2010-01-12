/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              This page details user information for an application.
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
    var userProfilesStore = new Ext.data.JsonStore ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('users_profile/' + appName), method: 'GET' }),
        autoLoad: true,
        root: 'data',
        fields: ['username', 'avg_daily_requests', 'number_of_requests', 'avg_nrows'],
        baseParams: {
            from: profileTimeframe.from().formatForServer(),
            to: profileTimeframe.to().formatForServer()
        },
        listeners: {
            'load': function (records) {
                var totalRequestsMade = 0;
                records.each (function (d) {
                    totalRequestsMade += d.get('number_of_requests') * 1;
                });
                records.each (function (d) {
                    d.set ('total_requests_percentage', (d.get('number_of_requests') * 1) / totalRequestsMade);
                });
            },
            'loadexception': jarvis.tracker.extStoreLoadExceptionHandler
        }
    });

    var userProfiles = new Ext.grid.GridPanel({
        store: userProfilesStore,
        title: 'User Profile Results',
        region: 'center', 
        height: 300,
        columns: [
            {
                header: 'Username',
                dataIndex: 'username',
                sortable: true
            },
            {
                header: 'Req. (%)',
                dataIndex: 'total_requests_percentage',
                sortable: true,
                renderer: function (x) { return (Math.round (x * 10000) / 100) + '%'; }
            },
            {
                header: 'Avg. Daily Requests',
                dataIndex: 'avg_daily_requests',
                sortable: true,
                renderer: function (x) { return (Math.round (x * 100) / 100); }
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
        title: appName + '- Users',
        layout: 'border',
        hideMode: 'offsets',
        closable: true,
        items: [
            userProfiles
        ]
    });

}; })();


