//============================================================================
// Description:
//      This is a utility file with helper methods for when using Jarvis with
//      ExtJS.  If using Flex, Dojo, or another toolkit, you would not use these
//      functions, you would write an equivalent interface to your own toolkit.
//
//
// Licence:
//      This file is part of the Jarvis WebApp/Database gateway utility.
//
//      Jarvis is free software: you can redistribute it and/or modify
//      it under the terms of the GNU General Public License as published by
//      the Free Software Foundation, either version 3 of the License, or
//      (at your option) any later version.
//
//      Jarvis is distributed in the hope that it will be useful,
//      but WITHOUT ANY WARRANTY; without even the implied warranty of
//      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//      GNU General Public License for more details.
//
//      You should have received a copy of the GNU General Public License
//      along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
//
//      This software is Copyright 2008 by Jonathan Couper-Smartt.
//============================================================================

// Default Values for EXT
// Default is from the extjs website.
Ext.BLANK_IMAGE_URL = '/edit/decoration/s.gif';

// Global parameters
var application = 'default';
var login_page  = 'login.html';
var jarvis_home = '/jarvis-bin/jarvis.pl';

// Init our parameters.
function jarvisInit (new_application, new_login_page) {
    if (new_application != null) {
        application = new_application;
    }
    if (new_login_page != null) {
        login_page = new_login_page;
    }
}

// URL builder.
function jarvisUrl (action_name, dataset_name) {
    var url = jarvis_home + '?app=' + application + '&action=' + action_name;
    if (dataset_name) {
        url = url + '&dataset=' + dataset_name;
    }
    return url;
}

// Alternate POST URL without args.
function jarvisPostUrl () {
    return jarvis_home;
}

// Fill the standard post params.  Caller can then add their own params.
function jarvisPostParams (action_name, dataset_name) {
    this.app = application;
    this.action = action_name;
    this.dataset = dataset_name;
}

// Store load failed.  Set this as your "loadexception" handler on your Stores
// and we will print out the exception message (probably 'need to login') and
// then will redirect to the login page.  If you have two stores, we'll only
// display the first error which arrives for that page.
//
var done_alert = 0;
function jarvisLoadException (proxy, options, response, e) {
    if (! done_alert) {
        alert (response.responseText);
        done_alert = 1;
    }
    document.location.href = login_page;
};

// Common submit method (does delete/update/insert).  Pass an array of
// changes of form hash of "key" => "value".  The key field must be present,
// and cannot of course be changed.
//
//      Use negative ID to specify deletion.
//      Use positive ID to specify update.
//      Use zero ID to specify insert.
//
function jarvisSendChange (store, dataset_name, fields, status_element, disable_component) {
    Ext.Ajax.request({
        url: jarvis_home,

        // We received a response back from the server, that's a good start.
        success: function (response, request) {

            // If we succeeded, then enable our component if there are no more changes.
            if (response.responseText == 'OK') {
                if ((store.getModifiedRecords().length == 0) && (disable_component != null)) {
                    disable_component.setDisabled (false);
                }

            // This indicates that not all updates succeeded.  Better reload store.
            // Assume that the store reload callback will enable the component.  We don't.
            } else {
                alert (response.responseText);
                store.reload ();
            }

            // In any case, reset the status element if there are no more changes.
            if ((store.getModifiedRecords().length == 0) && (status_element != null)) {
                status_element.innerHTML = '&nbsp';
            }
        },

        // Total failure.  Script failed.  It might have managed to update
        // our changes, but we have no way to tell.  Must reload store.
        failure: function () {
            alert ('Server responded with error.  Updates lost.');
            store.reload ();
        },

        params: {
            action: 'store',
            app: application,
            dataset: dataset_name,
            fields: Ext.util.JSON.encode (fields)
        }
    });
}

// Transaction Type = Remove.  Deletes a single row in the specified store.
function jarvisRemove (store, dataset_name, record, status_element, disable_component) {
    var fields = record.data;
    fields._transaction_type = 'remove';

    if (status_element != null) {
        status_element.innerHTML = '&nbsp;<b>DELETING...</b>';
    }
    if (disable_component != null) {
        disable_component.setDisabled (true);
    }
    jarvisSendChange (store, dataset_name, fields, status_element, disable_component);
}

// Transaction Type = Update.  Creates OR Updates a single row in the specified store.
function jarvisUpdate (store, dataset_name, record, status_element, disable_component) {
    var fields = record.data;
    fields._transaction_type = 'update';

    if (status_element != null) {
        status_element.innerHTML = '&nbsp;<b>UPDATING...</b>';
    }
    if (disable_component != null) {
        disable_component.setDisabled (true);
    }
    jarvisSendChange (store, dataset_name, fields, status_element, disable_component);
}

// Add a cookie.
function jarvisCreateCookie (name, value, days) {
    if (days) {
        var date = new Date();
        date.setTime(date.getTime()+(days*24*60*60*1000));
        var expires = "; expires="+date.toGMTString();

    } else {
        var expires = "";
    }
    document.cookie = name + "=" + value + expires + "; path=/";
}

// Read a cookie.
function jarvisReadCookie (name) {
    var nameEQ = name + "=";
    var ca = document.cookie.split (';');

    for (var i=0; i < ca.length; i++) {
        var c = ca[i];
        while (c.charAt(0)==' ')
            c = c.substring(1,c.length);

        if (c.indexOf(nameEQ) == 0)
            return c.substring(nameEQ.length,c.length);
    }
    return null;
}

// Wipe a cookie.  Set empty.
function jarvisEraseCookie(name) {
    jarvisCreateCookie (name, "", -1);
}
