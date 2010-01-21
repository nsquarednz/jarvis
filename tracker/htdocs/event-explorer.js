/**
 * Description: This ExtJS code is designed to be evaluated and embedded within another page.
 *              It provides an interactive and visual way to view the events that occured during
 *              a period of time, based on a set of filter criteria.
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

function displayTimeline(id) {
    var eventSource = new Timeline.DefaultEventSource(0);
    var theme = Timeline.ClassicTheme.create();
    var d = Timeline.DateTime.parseGregorianDateTime("Jan 12 2010 12:00:00")

    var bandInfos = [
        Timeline.createBandInfo({
            width:          "80%", 
            intervalUnit:   Timeline.DateTime.MINUTE, 
            intervalPixels: 400,
            eventSource:    eventSource,
            date:           d,
            theme:          theme,
            layout:         'original'  // original, overview, detailed
        }),
        Timeline.createBandInfo({
            width:          "10%", 
            intervalUnit:   Timeline.DateTime.HOUR, 
            intervalPixels: 200,
            eventSource:    eventSource,
            date:           d,
            theme:          theme,
            layout:         'overview'  // original, overview, detailed
        }),
        Timeline.createBandInfo({
            width:          "10%", 
            intervalUnit:   Timeline.DateTime.DAY, 
            intervalPixels: 400,
            eventSource:    eventSource,
            date:           d,
            theme:          theme,
            layout:         'overview'  // original, overview, detailed
        })
    ];
    bandInfos[1].syncWith = 0;
    bandInfos[2].syncWith = 0;
    bandInfos[1].highlight = true;
    bandInfos[2].highlight = true;
                
    tl = Timeline.create(document.getElementById(id), bandInfos, Timeline.HORIZONTAL);

    // Adding the date to the url stops browser caching 
    tl.loadJSON(jarvisUrl ('events') + '?' + (new Date().getTime()), function(json, url) {
        eventSource.loadJSON(json, url);
    });;
};

// This is the real function for creating a query page.
return function (appName, extra) {

    var timelineId = Ext.id();

    var center = new Ext.Panel({
        region: 'center',
        layout: 'fit',
        items: [
            new Ext.BoxComponent ({
                autoEl: { tag: 'div' },
                id: timelineId,
                cls: 'timeline-default',
                x: 0,
                y: 0,
                anchor: '100% 100%',
                listeners: {
                    render: function () {
                        displayTimeline.defer(1, this, [timelineId]); // Defer to force the component height to be maxed before the timeline renders.
                    }
                }
            })
        ]
    });

    return new Ext.Panel({
        title: 'Event Explorer',
        layout: 'border',
        closable: true,
        hideMode: 'offsets',
        items: [
            center
        ]
    })

}; })();


