/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides a summary page, summarising all of this jarvis's install.
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
return function () {

    var errorList = new Ext.ux.ErrorList ({
        region: 'east',
        width: '40%',
        split: true,
        collapsible: true,
        closable: true,
        title: 'Recent Errors',
        dataSourceParams: {
            limit: true
        }
    });

    var tps = {
        xtype: 'TimeBasedVisualisation',
        region: 'center',
        dataSource: {
            dataset: 'tps'
        },
        graph: new jarvis.graph.TpsGraph({
            listeners: {
                click: function(data) {
                    var path = 'root/events?from=' + (data.t - 1.0 / 48.0) + '&to=' + (data.t + 1.0 / 48.0);
                    jarvis.tracker.loadAndShowTabFromPath (path);
                }
            }
        }),
        graphConfig: {
            timeframe: jarvis.tracker.configuration.defaultDateRange.clone()
        }
    };

    return new Ext.Panel ({
        title: 'Applications',
        layout: 'border',
        hideMode: 'offsets',
        items: [
            errorList,
            tps
        ]
    });

}; })();
