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
    theme.event.bubble.width = 450;  

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
            eventSource.loadJSON(data, '');
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

        var lookups = ['sid', 'user', 'limit', 'app_name', 'from', 'to' ];
        Ext.each (lookups, function (e) {
            if (form.findById(e + '_' + timelineId).getValue())
                var v = form.findById(e + '_' + timelineId).getValue();
                if (v && ((typeof v === 'string' && v.length > 0) || true)) {
                    params[e] = Ext.isDate(v) ? v.formatForServer() : v;
                }
        });

        Ext.Ajax.request ({
            url: jarvisUrl ('get_earliest_event_time'),
            method: 'GET',
            params: params,
            success: function (xhr) { 
                var data = Ext.util.JSON.decode (xhr.responseText);
                if (data.data[0].t) {
                    form.timelineObject = displayTimeline (timelineId, Date.parseDate (data.data[0].t, 'Y-m-d H:i:s'), params);
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
    
    var form = new Ext.Panel({
        region: 'north',
        autoHeight: true,
        layout: 'column',
        bodyStyle: {
            padding: '5px'
        },
        defaults: {
            columnWidth: 0.33,
            layout: 'form',
            border: false,
            xtype:'panel',
            bodyStyle: 'padding:0 18px 0 0'
        },
        items: [
            {
                defaults: {
                    anchor: '100%'
                },
                items: [
                    new Ext.form.ComboBox({
                        fieldLabel: 'Application',
                        store: jarvis.tracker.applicationsInDatabase,
                        id: 'app_name_' + timelineId,
                        displayField: 'app_name',
                        allowBlank: 'false',
                        editable: false,
                        forceSelection: true,
                        value: extra.params.appName || ''
                    }),
                    new Ext.ux.form.DateTime ({
                        dateFormat: 'd/m/Y',
                        fieldLabel: 'From',
                        id: 'from_' + timelineId,
                        value: extra.params.from || '',
                        value: extra.params.sid ? '' : Date.parseDate(new Date().format('Y-m-d\\TH:00:00'), 'c')
                    }),
                    new Ext.ux.form.DateTime({
                        dateFormat: 'd/m/Y',
                        fieldLabel: 'To',
                        id: 'to_' + timelineId,
                        value: extra.params.to || '',
                        value: extra.params.sid ? '' : Date.parseDate(new Date().add(Date.HOUR, 1).format('Y-m-d\\TH:00:00'), 'c')
                    })
                ]
            },
            {
                defaults: {
                    anchor: '100%'
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
                ]
            },
            {
                defaults: {
                    anchor: '100%'
                },
                items: [
                    new Ext.form.ComboBox({
                        fieldLabel: 'Max. # of Events',
                        id: 'limit_' + timelineId,
                        value: extra.params.maxEvents || '',
                        store: [ '100', '500', '1000', '1500' ],
                        value: '500',
                        mode: 'local'
                    })
                ]
            }
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
                anchor: '100% 100%'
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
                if (form.timelineObject) {
                    setTimeout(function () { form.timelineObject.layout(); }, 0);
                }
            }
        }
    })

}; })();


