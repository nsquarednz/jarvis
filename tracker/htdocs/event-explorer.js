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


function displayTimeline(id, d, params, afterLoadCallback) {
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
            if (afterLoadCallback) {
                afterLoadCallback (data);
            }
        },
        failure: jarvis.tracker.extAjaxRequestFailureHandler
    });

    return Timeline.create(document.getElementById(id), bandInfos, Timeline.HORIZONTAL);
};

// This is the real function for creating a query page.
return function (appName, extra) {

    var timelineId = Ext.id();
    var form = null;
    var start = 0;

    var submitForm = function() {

        var params = {
            start: start
        };
        var lookups = ['sid', 'user', 'dataset', 'limit', 'app_name', 'from', 'to', 'text'];
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
                var dte = new Date();
                if (data.data[0].t) {
                    dte = Date.fromJulian (data.data[0].t)
                }
                form.timelineObject = displayTimeline (timelineId, dte, params, function (data) {
                    form.ownerCt.getBottomToolbar().items.get('resultsinfo').setText('Viewing ' + start + ' to '  + (start + data.events.length) + ' of ' + data.fetched + ' events');
                    window.mytb = form.ownerCt;

                    if (data.events.length > 0) {
                        form.timelineObject.getBand(0).setCenterVisibleDate(Timeline.DateTime.parseIso8601DateTime(data.events[0].start));
                    }
                });
            },
            failure: jarvis.tracker.extAjaxRequestFailureHandler
        });
    };
    
    var form = new Ext.Panel({
        region: 'north',
        autoHeight: true,
        border: false,
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
                        value: extra.params.from ? Date.fromJulian(extra.params.from) : 
                            (extra.params.sid ? '' : Date.parseDate(new Date().format('Y-m-d\\TH:00:00'), 'c'))
                    }),
                    new Ext.ux.form.DateTime({
                        dateFormat: 'd/m/Y',
                        fieldLabel: 'To',
                        id: 'to_' + timelineId,
                        value: extra.params.to ? Date.fromJulian(extra.params.to) : 
                            (extra.params.sid ? '' : Date.parseDate(new Date().add(Date.HOUR, 1).format('Y-m-d\\TH:00:00'), 'c'))
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
                    }),
                    new Ext.form.TextField({
                        fieldLabel: 'Dataset',
                        id: 'dataset_' + timelineId,
                        value: extra.params.dataset || ''
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
                        store: [ '100', '250', '500', '1000', '1500' ],
                        value: '250',
                        mode: 'local'
                    }),
                    new Ext.form.TextField({
                        fieldLabel: 'Text',
                        id: 'text_' + timelineId,
                        value: extra.params.text || ''
                    })
                ]
            }
        ],
        buttons: [
                    new Ext.Button ({
                        text: 'Show',
                        id: 'show',
                        'default': true,
                        listeners: {
                            click: submitForm
                        }
                    })
        ]
    });

    submitForm.defer(1);

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
        },
        bbar: [
            {
                xtype: 'label',
                id: 'resultsinfo',
                text: 'Viewing 0 of 0 events'
            },
            {
                xtype: 'tbfill'
            },
            {
                text: "Back",
                cls: 'x-btn-text-icon',
                icon: 'style/arrow_left.png',
                handler: function () { 
                    start -= form.findById('limit_' + timelineId).getValue();
                    start = start < 0 ? 0 : start;
                    submitForm();
                }
            },
            {
                xtype: 'tbbutton',
                text: "Forward",
                cls: 'x-btn-text-icon',
                icon: 'style/arrow_right.png',
                handler: function () { 
                    start += 1 * form.findById('limit_' + timelineId).getValue();
                    submitForm();
                }
            }
        ]
    })

}; })();


