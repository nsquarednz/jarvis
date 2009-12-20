/**
 * This ExtJS code is designed to be evaluated and embedded within another page.
 *
 * It provides a page describing a dataset query.
 */

(function () {
return function (appName, extra) {
    var center = new Ext.Panel({
        region: 'center',
        items: [{
            html: "blabla"
        }]
    });

    var queryLoader = function (type, element) {
        Ext.Ajax.request ({
            url: jarvisUrl('source/' + appName + '/' + type + '/' + extra.query),
            success: function (xhr) {
                var html = xhr.responseText;
                html = prettyPrintOne(html);
                element.update("<code class='prettyprint'>" + html + "</code>");
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
        width: 400,
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
                            tag: 'div'
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

    return new Ext.Panel ({
        layout: 'fit',
        title: appName + " - " + extra.query,
        items: [ 
            new Ext.Panel({
                layout: 'border',
                closable: true,
                items: [
                    codeView,
                    center
                ]
            })
        ]
    });

}; })();

