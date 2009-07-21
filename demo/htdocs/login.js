Ext.onReady (function () {
    jarvisInit ('demo');

    // this holds our status record
    var status_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('__status'),
        root: 'data',
        idProperty: 'username',
        fields: ['logged_in', 'username', 'error_string', 'group_list']
    });

    // this holds our staff names
    var user_names_store = new Ext.data.JsonStore ({
        url: jarvisUrl ('user_names'),
        root: 'data',
        idProperty: 'id',
        fields: ['id', 'name'],
        displayField: 'name'
    });

    var username_field = new Ext.form.ComboBox ({
        renderTo: 'username',
        store: user_names_store,
        emptyText: 'Select Username...',
        displayField: 'name',
        valueField: 'name',
        mode: 'local',
        forceSelection: true
    });
    var password_field = new Ext.form.TextField ({
        renderTo: 'password'
    });

    // Attempt to login.  Set our cookies, and reload the "status" store.
    function doLogin () {
        // alert ('Login ' + username_field.getValue() + ' + ' + password_field.getValue());
        status_store.baseParams.app = 'demo';
        status_store.baseParams.action = 'status';
        status_store.baseParams.username = username_field.getValue ();
        status_store.baseParams.password = password_field.getValue ();
        status_store.reload ();
    }
    function doLoginOnEnter (field, e) {
        if (e.getKey () == Ext.EventObject.ENTER) {
            doLogin ();
        }
    }
    function storeLoaded () {
        var error_string = status_store.getAt (0).data.error_string;
        var group_list = status_store.getAt (0).data.group_list;

        document.getElementById ("error_text").innerHTML = error_string;
        if (error_string == '') {
            var outgoing = '<p>Login Accepted.';
            if (group_list != '') {
                outgoing = outgoing + '  Groups = ' + group_list + '.';
            }
            outgoing = outgoing + '</p>\n';
            outgoing = outgoing + '<p>Proceed to the <a href="index.html">Index</a>.</p>\n';
            if (document.referrer != '') {
                outgoing = outgoing + '<p>Return to <a href="' + document.referrer + '">' + document.referrer + '</a>.</p>\n';
            }
            document.getElementById ("outgoing_text").innerHTML = outgoing;

        } else {
            document.getElementById ("outgoing_text").innerHTML = 'Login is required.<p>\n';
        }
    };
    function storeLoadException (proxy, options, response, e) {
        document.getElementById ("error_text").innerHTML = response.responseText;
    };

    username_field.setValue (jarvisReadCookie ('username'));
    password_field.setValue (jarvisReadCookie ('password'));

    password_field.addListener("specialkey", doLogin);

    status_store.addListener("load", storeLoaded);
    status_store.addListener("loadexception", storeLoadException);
    status_store.load();

    user_names_store.addListener("loadexception", storeLoadException);
    user_names_store.load();
});
