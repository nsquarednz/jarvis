/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides a page describing a dataset.
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

    var center = new Ext.Panel({
        region: 'center',
        layout: 'fit',
        items: [
            {
                xtype: 'Visualisation',
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
                var html = xhr.responseText;
                element.update("<pre class='sh_sql'>" + html + "</pre>");
                sh_highlightElement(element.first().dom, sh_languages['sql']);
            },
            failure: function () {
                Ext.Msg.alert ("Cannot load: " + appName + '/' + type + '/' + extra.query);
            }
        });
    };

    var codeView = new Ext.Panel({
        region: 'east',
        layout: 'accordion',
        split: true,
        collapsible: true,
        width: 600,
        title: "Dataset Code",
        items: new Array()
    });

    ['Select', 'Insert', 'Update', 'Delete'].map (function (t) {
        var p = new Ext.Panel({
                title: t,
                layout: 'fit',
                autoScroll: true,
                items: [
                    new Ext.BoxComponent ({
                        autoEl: {
                            tag: 'div',
                            id: Ext.id()
                        },
                        anchor: '100% 100%',
                        x: 100, y: 45,
                        listeners: {
                            render: function () { queryLoader(t.toLowerCase(), this.getEl()); }
                        }
                    })
                ]
            });
        codeView.add(p);
    });

    return new Ext.Panel({
        title: appName + " - " + extra.query,
        layout: 'border',
        closable: true,
        hideMode: 'offsets',
        items: [
            codeView,
            center
        ]
    })

}; })();

