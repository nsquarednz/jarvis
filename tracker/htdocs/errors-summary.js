/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              This provides an Ext Container for a summary of information  on errors from 
 *              an application.
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

    var initialDate = extra && extra.params && extra.params.date ? Date.parseDate (extra.params.date, 'c').clearTime() : null;

    // create the main Data Store for the fan list
    var recentErrorsStore = new Ext.data.Store ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('errors/' + appName), method: 'GET' }),
        autoLoad: true,
        baseParams: {},
        reader: new Ext.data.JsonReader ({
            root: 'data',
            id: 'id',
            totalProperty: 'fetched',
            fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'params', 'post_body', 'message']
        }),
        listeners: {
            'loadexception': jarvis.tracker.extStoreLoadExceptionHandler,
            'beforeload': function () {
                delete this.baseParams.limit_to_date;
                if (this.dateParamAsDate) {
                    this.baseParams.limit_to_date = this.dateParamAsDate.formatForServer();
                }
            }
        },
        initialSelection: extra && extra.params ? extra.params.id : null, // Our own property for the initial ID to select.
        dateParamAsDate: initialDate // Our own property as well
    });

    var errorDetailsTemplate = new Ext.Template (
        '<table>',
        '  <tr><th>Event Time</th><td>{start_time}</td></tr>',
        '  <tr><th>Username</th><td>{username}</td>',
        '      <th>SID</th><td>{sid}</td></tr>',
        '  <tr><th>User Groups</th><td colspan="3">{group_list}</td></tr>',
        '  <tr><th>Dataset</th><td colspan="3">{dataset}</td></tr>',
        '  <tr><th>Request Parameters</th><td colspan="3">{params}</td></tr>',
        '  <tr><th>Post Body</th><td colspan="3">{post_body}</td></tr>',
        '  <tr><th>Error Message</th><td colspan="3"><pre>{message}</pre></td></tr>',
        '</table>'
    );

    var recentErrorDetailsId = Ext.id();

    var showErrorDetails = function(record) {
        errorDetailsTemplate.overwrite (recentErrorDetailsId, record.json);
    };

    var recentErrorsList = new Ext.grid.GridPanel({
        store: recentErrorsStore,
        border: false,
        region: 'center', 
        columns: [
            {
                header: 'Event Time',
                dataIndex: 'start_time',
                sortable: true,
                width: 20,
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
                renderer: function (x) { return Ext.util.Format.ellipsis (x, 150); }
            }
        ],
        viewConfig: {
            forceFit: true
        },
        tbar: [
            'Viewing: ',
            new Ext.form.DateField({
                format: 'd/m/Y',
                value: initialDate,
                altFormats: 'd/m/Y|n/j/Y|n/j/y|m/j/y|n/d/y|m/j/Y|n/d/Y|m-d-y|m-d-Y|m/d|m-d|md|mdy|mdY|d|Y-m-d',
                listeners: {
                    specialkey: function (field, e) {
                        if (e.getKey() == Ext.EventObject.ENTER) {
                            recentErrorsStore.dateParamAsDate = field.getValue() || null;
                            recentErrorsStore.load();
                        }
                    },
                    select: function (field, e) {
                        recentErrorsStore.dateParamAsDate = e;
                        recentErrorsStore.load();
                    }
                }
            }),
            {xtype: 'tbfill'},
            'Filter: ',
            new Ext.form.TextField( {
                listeners: {
                    specialkey: function (field, e) {
                        if (e.getKey() == Ext.EventObject.ENTER) {
                            recentErrorsStore.baseParams.filter = field.getValue();
                            recentErrorsStore.load();
                        }
                    }
                }
            })
        ],
        sm: new Ext.grid.RowSelectionModel({
                singleSelect:true,
                listeners: {
                    rowselect: function (sm, rowIndex, r) {
                        showErrorDetails (r);
                    }
                }
            })
    });
 
    // event handler that, after load, will see if we want to select a specific
    // row, and if so will then do it.
    recentErrorsStore.on ('load', function () {
        if (this.initialSelection) {
            var record = this.getById (this.initialSelection * 1);
            recentErrorsList.getSelectionModel().selectRecords ([record]);
        }
    });

    return new Ext.Panel ({
        title: appName + ' - Errors',
        layout: 'border',
        closable: true,
        items: [
            recentErrorsList,
            new Ext.Panel ({
                layout: 'fit',
                border: false,
                region: 'south',
                title: 'Error Details',
                collapsible: true,
                height: 300,
                split: true,
                items: [
                    {
                        xtype: 'container',
                        id: recentErrorDetailsId,
                        autoEl: {
                            html: '&nbsp;',
                            tag: 'div',
                            cls: 'error-details'
                        }
                    }
                ]
            })
        ],
        listeners: {
            updateparameters: function (p) {
                if (p.params) {
                    recentErrorsStore.initialSelection = p.params.id
                    var d = p.params.date ? Date.parseDate (p.params.date, 'c').clearTime() : null;
                    if ((!recentErrorsStore.dateParamAsDate && d) || // If we have no previous date but do now
                        (d && recentErrorsStore.dateParamAsDate && 
                            d.getTime() != recentErrorsStore.dateParamAsDate.getTime())) { // or the dates are not the same
                        recentErrorsStore.dateParamAsDate = d;
                        recentErrorsStore.load();
                    } else {
                        // If we don't need to load, just set the correct selection.
                        var record = recentErrorsStore.getById (p.params.id * 1);
                        recentErrorsList.getSelectionModel().selectRecords ([record]);
                    }
                }
            }
        }
    });

}; })();
