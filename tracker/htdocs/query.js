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
                ret.push ([ m[1], '', true]); // [ parameter name, parameter value, null on empty ]
            }
            m = re.exec(sql);
        }
        return ret;
    };

    /**
     * This function replaces parameters with real values, if so
     * desired, and then shows this onscreen. Could be split into
     * two separate functions if they need to be separated at any
     * point.
     */
    var displaySql = function  (element) {
        var parameterise = element.showParameterised;
        var dsql = element.queryParamsStore.sql;
        if (parameterise) {
            element.queryParamsStore.each (function (r) {
                var re = new RegExp('\{[\{]?[\$]?' + r.get('param') + '[\}]?\}', 'g');
                if (r.get('nullOnEmpty') && (!r.get('value') || r.get('value') === '')) {
                    dsql = dsql.replace (re, 'NULL');
                } else {
                    dsql = dsql.replace (re, "'" + r.get('value') + "'");
                }
            });
        }

        element.getEl().update('<pre class="sh_sql">' + dsql + '</pre>');
        sh_highlightElement(element.getEl().first().dom, sh_languages['sql']);
    };

    /**
     * This function executes a query using the parameters provided by the user.
     * and then shows the results of the query in the 'results' tab on the queries
     * accordion page.
     */
    var executeQuery = function (info) {
        var url = jarvis_home + '/' + info.app + '/' + info.query;
        var params = {};
        var restArgs = [];
        var maxRestArg = -1;
        
        info.params.each (function (r) {
            if (r.get('nullOnEmpty') && (!r.get('value') || r.get('value') === '')) {
                // do nothing for null's
            } else {
                var p = r.get('param');
                if (p > 0) {
                    restArgs [p] = r.get('value');
                    maxRestArg = p > maxRestArg ? p : maxRestArg;
                } else {
                    params[p] = r.get('value');
                }
            }
        });
        for (var i = 1; i <= maxRestArg; ++i) {
            url += '/' + (restArgs[i] ? restArgs[i] : '');
        }

        Ext.Ajax.request ({
            url: url,
            method: 'GET',
            params: params,
            success: function (xhr) { 
                var txt = xhr.responseText;
                // TODO: Maybe show results in a table, if desirable.
                var height = info.target.getEl().getBox().height;
                try {
                    Ext.util.JSON.decode (txt); // Throws error on failure
                    info.target.getEl().update('<pre class="sh_javascript">' + txt + '</pre>');
                    sh_highlightElement(info.target.getEl().first().dom, sh_languages['javascript']);
                } catch (error) {
                    // On error, assume XML (the other format available from Jarvis).
                    // The result could be an error string, in which case it may just
                    // show up with a bit of color.
                    info.target.getEl().update('<pre class="sh_xml">' + Ext.util.Format.htmlEncode(txt) + '</pre>');
                    sh_highlightElement(info.target.getEl().first().dom, sh_languages['xml']);
                }

                // If the results tab is not active, make it active.
                if (info.target.ownerCt && info.target.ownerCt.activate) {
                    info.target.ownerCt.activate (info.target);
                }
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        });
    };

// This is the real function for creating a query page.
return function (appName, extra) {

    var center = new Ext.Panel({
        region: 'center',
        layout: 'anchor',
        items: [
            {
                xtype: 'Visualisation',
                anchor: '100%',
                height: 100,
                dataSource: {
                    dataset: 'dataset_duration/' + appName + '/' + extra.query
                },
                graph: new jarvis.graph.DatasetPerformanceGraph()
            },
            {
                xtype: 'TimeBasedVisualisation',
                anchor: '100% -100',
                dataSource: {
                    dataset: 'tps/' + appName + '/' + extra.query
                },
                graph: new jarvis.graph.TpsGraph(),
                graphConfig: {
                    timeframe: jarvis.tracker.configuration.defaultDateRange.clone()
                }
            }
        ]
    });

    var queryLoader = function (type, element) {
        var url = jarvisUrl('source/' + appName + '/' + type + '/' + extra.query);
        Ext.Ajax.request ({
            url: url,
            success: function (xhr) {
                element.queryParamsStore.sql = xhr.responseText;
                var parameters = parseSqlForParameters (element.queryParamsStore.sql);
                element.queryParamsStore.loadData (parameters);
                displaySql(element);
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
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
        width: '50%',
        title: 'Dataset Code',
        hideMode: 'offsets',
        items: new Array()
    });

    // For each of the available query types, create an accordion panel for it.
    ['Select', 'Insert', 'Update', 'Delete'].map (function (t) {
        var paramsStore = new Ext.data.SimpleStore({
            fields: ['param', 'value', 'nullOnEmpty']
        });

        var parameterisedSqlBoxId = Ext.id();
        var parameterisedSqlBox = new Ext.BoxComponent ({
            title: 'Parameterised SQL', 
            autoScroll: true,
            queryParamsStore: paramsStore,
            showParameterised: true,
            autoEl: {
                tag: 'div',
                id: parameterisedSqlBoxId,
                cls: 'codeView'
            }
        });

        paramsStore.on('datachanged', displaySql.createCallback(parameterisedSqlBox));
        paramsStore.on('update', displaySql.createCallback(parameterisedSqlBox));

        var sqlBoxId = Ext.id();
        var sqlBox = new Ext.BoxComponent ({
            title: 'SQL', 
            autoScroll: true,
            queryParamsStore: paramsStore,
            showParameterised: false,
            autoEl: {
                tag: 'div',
                id: sqlBoxId,
                cls: 'codeView'
            },
            listeners: {
                render: function () { queryLoader(t.toLowerCase(), this); }
            }
        });

        var resultsBox = new Ext.BoxComponent ({
            title: 'Results', 
            autoScroll: true,
            autoEl: {
                tag: 'div',
                cls: 'codeView'
            }
        });

        var paramsGrid = new Ext.grid.EditorGridPanel({
            store: paramsStore,
            stripeRows: true,
            anchor: '100%',
            height: 150,
            clicksToEdit: 1,
            viewConfig: {
                forceFit: true
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
                    xtype: 'tbfill'
                },
                {
                    text: 'Execute',
                    handler: executeQuery.createCallback ({
                        app: appName,
                        query: extra.query,
                        params: paramsStore,
                        target: resultsBox
                    })
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
                    paramsGrid,
                    new Ext.TabPanel ({
                        deferredRender: false,
                        anchor: "100% -150",
                        enableTabScroll: true,
                        layoutOnTabChange: true,
                        activeTab: 0,
                        items: [
                            sqlBox,
                            parameterisedSqlBox,
                            resultsBox
                        ]
                    })
                ]
            };
        codeView.add(p);
    });

    return new Ext.Panel({
        title: appName + ' - Queries - ' + extra.query,
        layout: 'border',
        closable: true,
        hideMode: 'offsets',
        items: [
            codeView,
            center
        ]
    })

}; })();

