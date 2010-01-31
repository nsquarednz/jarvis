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


function displayTimeline(id, d, params) {
    var eventSource = new Timeline.DefaultEventSource(0);
    var theme = Timeline.ClassicTheme.create();

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
                
    Ext.Ajax.request ({
        url: jarvisUrl ('events'),
        method: 'GET',
        params: params,
        success: function (xhr, req) { 
            var data = Ext.util.JSON.decode (xhr.responseText);
            eventSource.loadJSON(data, req.url);
        },
        failure: jarvis.tracker.extAjaxRequestFailureHandler
    });

    return Timeline.create(document.getElementById(id), bandInfos, Timeline.HORIZONTAL);
};

// This is the real function for creating a query page.
return function (appName, extra) {

    var timelineId = Ext.id();
    var form = null;
    
    var submitForm = function() {
        var params = { };
        if (form.findById('sid_' + timelineId).getValue())
            params.sid = form.findById('sid_' + timelineId).getValue();
        if (form.findById('user_' + timelineId).getValue())
            params.user = form.findById('user_' + timelineId).getValue();

        Ext.Ajax.request ({
            url: jarvisUrl ('get_earliest_event_time'),
            method: 'GET',
            params: params,
            success: function (xhr) { 
                var data = Ext.util.JSON.decode (xhr.responseText);
                if (data.data[0].t) {
                    form.timelineObject = displayTimeline (timelineId, Date.parseDate (data.data[0].t, 'Y-m-d H:i:s'), params);
                    console.log ('form is', form);
                } else {
                    Ext.Msg.show ({
                        title: 'No data',
                        msg: 'Cannot find data matching search terms',
                        buttons: Ext.Msg.OK,
                        icon: Ext.Msg.INFO
                    });
                }
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        });
    };
    
    var form = new Ext.form.FormPanel({
        region: 'north',
        autoHeight: true,
        bodyStyle: {
            padding: '5px',
        },
        defaults: {
            width: 250
        },
        items: [
            new Ext.form.TextField({
                fieldLabel: 'SID',
                id: 'sid_' + timelineId,
                value: extra.params.sid || ''
            }),
            new Ext.form.TextField({
                fieldLabel: 'User',
                id: 'user_' + timelineId,
                value: extra.params.user || ''
            })
        ],
        buttons: [
            {
                text: 'Show',
                id: 'show',
                'default': true,
                listeners: {
                    click: submitForm
                }
            }
        ]
    });

    if (extra.params.sid || extra.params.user) {
        submitForm();
    }

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
            })
        ]
    });

    return new Ext.Panel({
        title: 'Event Explorer #' + extra.eventExplorerNumber,
        layout: 'border',
        closable: true,
        hideMode: 'offsets',
        items: [
            form,
            center
        ],
        listeners: {
            resize: function () {
                setTimeout(function () {
                    form.timelineObject.layout();
                }, 0);
            }
        }
    })

}; })();


