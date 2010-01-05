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

    return new Ext.Panel ({
        title: appName + '- Queries',
        layout: 'border',
        hideMode: 'offsets',
        closable: true,
        items: [
            {
                xtype: 'TimeBasedVisualisation',
                region: 'center',
                dataSource: {
                    dataset: 'tps/' + appName,
                },
                graph: new jarvis.graph.TpsGraph(),
                graphConfig: {
                    timeframe: trackerConfiguration.defaultDateRange.clone()
                }
            }
        ]
    });

}; })();

