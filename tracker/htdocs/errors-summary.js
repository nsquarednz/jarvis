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

    var limit = 50;

    var initialDate = extra && extra.params && extra.params.date ? Date.parseDate (extra.params.date, 'c').clearTime() : null;

    var recentErrorsStore = new Ext.data.Store ({
        proxy: new Ext.data.HttpProxy ({ url: jarvisUrl ('errors/' + appName), method: 'GET' }),
        autoLoad: false,
        reader: new Ext.data.JsonReader ({
            root: 'data',
            id: 'id',
            totalProperty: 'fetched',
            fields: ['sid', 'app_name', 'group_list', 'dataset', 'action', 'start_time', 'username', 'params', 'post_body', 'message']
        }),
        listeners: {
            'loadexception': jarvis.tracker.extStoreLoadExceptionHandler,
        },
        initialSelection: extra && extra.params ? extra.params.id : null, // Our own property for the initial ID to select.
        dateParamAsDate: initialDate // Our own property as well
    });

    function findErrorsInStream () {
        Ext.Ajax.request ({
            url: jarvisUrl ('find_specific_error/' + appName),
            method: 'GET',
            params: {
                id: recentErrorsStore.initialSelection,
                date: recentErrorsStore.dateParamAsDate.formatForServer(),
                filter: recentErrorsStore.baseParams.filter
            },
            success: function (xhr, req) { 
                var data = Ext.util.JSON.decode (xhr.responseText);
                if (data.fetched * 1 != 1) {
                    recentErrorsStore.load({
                        params: { start: 0, limit: limit }
                    }); // No data found, just load what we have already
                    return;
                }

                var numberIn = data.data[0].number_in * 1;
                var page = Math.floor(numberIn / limit);
                recentErrorsStore.load({
                    params: { start: page * limit, limit: limit }
                });
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        });
    }

    if (recentErrorsStore.initialSelection || recentErrorsStore.dateParamAsDate) {
        findErrorsInStream();
    } else {
        recentErrorsStore.load({
            params: { start: 0, limit: limit }
        });
    }

    var errorDetailsTemplate = new Ext.XTemplate (
        '<table>',
        '  <tr><th>Event Time</th><td>{start_time}</td></tr>',
        '  <tr><th>Username</th><td>{username}</td>',
        '      <th>SID</th><td>{sid}</td></tr>',
        '  <tr><th>User Groups</th><td colspan="3">{group_list}</td></tr>',
        '  <tr><th>Dataset</th><td colspan="3">{dataset}</td></tr>',
        '  <tr><th>Error Message</th><td colspan="3"><code>{message}</code></td></tr>',
        '  <tr><th>Request Parameters</th><td colspan="3"><table class="error-details-params">',
        '  <tpl for="params">',
        '    <tr><td class="edp-key">{key}</td><td width="100%">{value}</td></tr>',
        '  </tpl></table>',
        '  <tr><th>Post Body</th><td colspan="3">{post_body}</td></tr>',
        '</table>'
    );

    var recentErrorDetailsId = Ext.id();

    var showErrorDetails = function(record) {
        var data = {
            username: record.json.username,
            sid: record.json.sid,
            group_list: record.json.group_list,
            start_time: Date.parseDate(record.json.start_time, 'c'),
            dataset: record.json.dataset,
            message: record.json.message,
            params: [],
            post_body: record.json.post_body
        };

        Ext.each (record.json.params.split(':'),
        function (a) {
            var p = a.split ('=');
            data.params.push ({key: p[0], value: p[1]});
        });

        errorDetailsTemplate.overwrite (recentErrorDetailsId, data);
    };

    var filterField = new Ext.form.TextField( {
        listeners: {
            specialkey: function (field, e) {
                if (e.getKey() == Ext.EventObject.ENTER) {
                    recentErrorsStore.baseParams.filter = field.getValue();
                    recentErrorsStore.load({
                        params: { start: 0, limit: limit }
                    });
                }
            }
        }
    });

    var pagingRenderered = false;
    var paging = new Ext.PagingToolbar({
        store: recentErrorsStore,
        pageSize: limit,
        displayInfo: true,
        displayMsg: 'Displaying errors {0} - {1} of {2}',
        emptyMsg: "No errors found",
        listeners: {
            render: function () {
                if (!pagingRenderered) {
                    this.add(
                        '-', 'Go to:', ' ', 
                        new Ext.form.DateField ({
                            format: 'd/m/Y',
                            value: initialDate,
                            altFormats: 'd/m/Y|n/j/Y|n/j/y|m/j/y|n/d/y|m/j/Y|n/d/Y|m-d-y|m-d-Y|m/d|m-d|md|mdy|mdY|d|Y-m-d',
                            listeners: {
                                specialkey: function (field, e) {
                                    if (e.getKey() == Ext.EventObject.ENTER) {
                                        recentErrorsStore.dateParamAsDate = field.getValue() || null;
                                        findErrorsInStream();
                                    }
                                },
                                select: function (field, e) {
                                    recentErrorsStore.dateParamAsDate = e;
                                    findErrorsInStream();
                                }
                            }
                        }),
                        '-', 'Filter:', ' ', filterField,
                        {
                            icon: 'style/cross.png',
                            tooltip: 'clear filter',
                            text: '&nbsp;&nbsp;',
                            listeners: {
                                click: function () {
                                    recentErrorsStore.baseParams.filter = '';
                                    filterField.setValue('');
                                    recentErrorsStore.load({
                                        params: { start: 0, limit: limit }
                                    });
                                }
                            }
                        }
                    );
                    pagingRenderered = true;
                }
            }
        }
    });


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
            forceFit: true,
            getRowClass : function (row, index) { 
              var cls = ''; 
              var data = row.data; 

              return 'grid-old';
           } 
        },
        sm: new Ext.grid.RowSelectionModel({
            singleSelect:true,
            listeners: {
                rowselect: function (sm, rowIndex, r) {
                    showErrorDetails (r);
                }
            }
        }),
        bbar: paging,
        listeners: {
            rowdblclick: function (g, i) {
                var record = g.store.getAt (i);
                var path = appName + '/Events?sid=' + record.get ('sid');
                jarvis.tracker.loadAndShowTabFromPath (path);
            }
        }
    });
 
    // event handler that, after load, will see if we want to select a specific
    // row, and if so will then do it.
    recentErrorsStore.on ('load', function () {
        if (this.initialSelection) {
            var record = this.getById (this.initialSelection * 1);
            recentErrorsList.getSelectionModel().selectRecords ([record]);
            this.initialSelection = null;
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
                    recentErrorsStore.dateParamAsDate = p.params.date ? Date.parseDate (p.params.date, 'c').clearTime() : null;
                    findErrorsInStream();
                }
            }
        }
    });

}; })();

