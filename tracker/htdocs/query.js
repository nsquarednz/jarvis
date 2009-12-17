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

    var codeView = new Ext.Panel({
        region: 'east',
        layout: 'accordion',
        width: 400,
        title: "Dataset Code",
        items: [{
            title: 'bla',
            html: 'bla'
        },
        {
            title: 'bla',
            html: 'bla'
        }]
    });

    return new Ext.Panel ({
        title: appName + " - " + extra.query,
        layout: 'border',
        closable: true,
        items: [
            codeView,
            center
        ]
    });

}; })();

