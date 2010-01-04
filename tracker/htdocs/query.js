/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides an Ext Container describing a dataset.
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
     * Helper function to parse a Jarvis SQL query for query parameters
     * of the syntax {{ .... }} , {{$ .... }}   or {$ ... }
     * and returns an array of maps, one for each parameter.
     */
    var parseSqlForParameters = function (sql) {
        var re = /\{[\{]?[\$]?([^\}]+)[\}]?\}/g;
        var m = re.exec (sql);
        var parameters = {};
        var ret = [];
        while (m) {
            if (!parameters[m[1]]) {
                parameters[m[1]] = 1;
                ret.push ([ m[1], '', true]);
            }
            m = re.exec(sql);
        }
        return ret;
    };

    var displaySql = function  (element) {
        var parameterise = element.showParameterised;
        var dsql = element.sql;

        if (parameterise) {
            element.queryParamsStore.each (function (r) {
                var re = new RegExp("\{[\{]?[\$]?" + r.get('param') + "[\}]?\}", "g");
                if (r.get('nullOnEmpty') && (!r.get('value') || r.get('value') === '')) {
                    dsql = dsql.replace (re, 'NULL');
                } else {
                    dsql = dsql.replace (re, "'" + r.get('value') + "'");
                }
            });
        }

        element.getEl().update("<pre class='sh_sql'>" + dsql + "</pre>");
        sh_highlightElement(element.getEl().first().dom, sh_languages['sql']);
    };

return function (appName, extra) {

    var center = new Ext.Panel({
        region: 'center',
        layout: 'anchor',
        items: [
            {
                xtype: 'Visualisation',
                anchor: '100%',
                height: 90,
                dataSource: {
                    dataset: "dataset_duration/" + appName + "/" + extra.query,
                },
                graph: new jarvis.graph.DatasetPerformanceGraph()
            },
            {
                xtype: 'TimeBasedVisualisation',
                anchor: '100% -100',
                dataSource: {
                    dataset: "tps/" + appName + "/" + extra.query,
                },
                graph: new jarvis.graph.TpsGraph(),
                graphConfig: {
                    timeframe: trackerConfiguration.defaultDateRange.clone()
                }
            }
        ]
    });

    var queryLoader = function (type, element) {
        Ext.Ajax.request ({
            url: jarvisUrl('source/' + appName + '/' + type + '/' + extra.query),
            success: function (xhr) {
                element.sql = xhr.responseText;
                var parameters = parseSqlForParameters (element.sql);
                element.queryParamsStore.loadData (parameters);
                displaySql(element, false);
            },
            failure: function () {
                Ext.Msg.alert ("Cannot load: " + appName + '/' + type + '/' + extra.query);
            }
        });
    };

    var codeView = new Ext.Panel({
        region: 'east',
        layout: 'accordion',
        layoutConfig: {
            animate: true
        },
        split: true,
        collapsible: true,
        width: 600,
        title: "Dataset Code",
        hideMode: 'offsets',
        items: new Array()
    });

    ['Select', 'Insert', 'Update', 'Delete'].map (function (t) {
        var paramsStore = new Ext.data.SimpleStore({
            fields: ['param', 'value', 'nullOnEmpty']
        });
        var sqlBoxId = Ext.id();
        var sqlBox = new Ext.BoxComponent ({
            anchor: '100% -110',
            autoScroll: true,
            queryParamsStore: paramsStore,
            showParameterised: false,
            autoEl: {
                tag: 'div',
                id: sqlBoxId,
                cls: 'codeView'
            },
            listeners: {
                render: function () { queryLoader(t.toLowerCase(), this); },
            }
        });
        var paramsGrid = new Ext.grid.EditorGridPanel({
            store: paramsStore,
            stripeRows: true,
            anchor: '100%',
            height: 150,
            clicksToEdit: 1,
            viewConfig: {
                forceFit: true,
            },
            columns: [
                {
                    header: 'Parameter',
                    dataIndex: 'param',
                    sortable: true
                },
                {
                    header: 'Value',
                    dataIndex: 'value',
                    editor: new Ext.form.TextField()
                },
                {
                    header: 'Null',
                    dataIndex: 'nullOnEmpty',
                    editor: new Ext.form.Checkbox()
                }
            ],
            bbar: [
                {
                    text: 'Show:',
                    xtype: 'label'
                },
                {
                    toggleGroup: 'queryShowFormat',
                    text: 'Source',
                    pressed: true,
                    handler: function () { sqlBox.showParameterised = false; displaySql (sqlBox); }
                },
                {
                    toggleGroup: 'queryShowFormat',
                    text: 'Parameterised',
                    handler: function () { sqlBox.showParameterised = true; displaySql (sqlBox); }
                },
                { 
                    xtype: 'tbfill'
                }
                /*{ TODO one day. It isn't trivial to select text for a user to copy.
                    text: 'Select',
                    handler: function () { 
                        range = document.createRange();
                        referenceNode = Ext.get(sqlBoxId).dom;
                        range.selectNodeContents (referenceNode);
                    }
                }*/
            ],
            listeners: {
                afteredit: function () { displaySql(sqlBox); }
            },
            sm: new Ext.grid.RowSelectionModel({singleSelect:true})
        });

        var p = {
                title: t,
                layout: 'anchor',
                border: false,
                hideMode: 'offsets',
                deferredRender: false,
                layoutConfig: {
                    columns: 1
                },
                items: [
                    paramsGrid
                    , sqlBox
                ]
            };
        codeView.add(p);
    });

    return new Ext.Panel({
        title: appName + " - Queries - " + extra.query,
        layout: 'border',
        closable: true,
        hideMode: 'offsets',
        items: [
            codeView,
            center
        ]
    })

}; })();

