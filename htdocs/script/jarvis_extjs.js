//============================================================================
// Description:
//      This is a utility file with helper methods for when using Jarvis with
//      ExtJS.  If using Flex, Dojo, or another toolkit, you would not use these
//      functions, you would write an equivalent interface to your own toolkit.
//
//      Note that this is not a core part of Jarvis.  Many of these
//      "helper" functions include some specific behaviour which suited my
//      use of Jarvis, but might not suit yours.
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
Ext.BLANK_IMAGE_URL = '/ext/resources/images/default/s.gif';

// Global parameters
var application = 'default';
var login_page  = 'login.html';
var jarvis_home = '/jarvis-bin/jarvis.pl';

// Track how many changes we still have outstanding.
var num_pending = 0;

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
function jarvisUrl (dataset_name) {
    var url = jarvis_home + '/' + application;
    if (dataset_name) {
        url = url + '/' + dataset_name;
    }
    return url;
}

// Gets a parameter by looking at the #<name> part of a full URL specification.
// Note that this method does NOT take any notice of regular '?' query parameters,
// it is totally separate.
//
function jarvisHashArg (url, arg_name, default_value) {
    // This is the part after "#", we use this for our query parameters,
    // e.g. which ID to load when editing details.
    var args = Ext.urlDecode (url.substring(url.indexOf('#')+1, url.length));
    if (args[arg_name]) {
        return args[arg_name];
    }
    return default_value;
}

// This is the '?' equivalent.
function jarvisQueryArg (url, arg_name, default_value) {
    var args = Ext.urlDecode (url.substring(url.indexOf('?')+1, url.length));
    if (args[arg_name]) {
        return args[arg_name];
    }
    return default_value;
}

// This checks # and then ?
function jarvisArg (url, arg_name, default_value) {
    return jarvisHashArg (url, arg_name) || jarvisQueryArg (url, arg_name, default_value);
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

    // Perform the request over ajax.
    Ext.Ajax.request({
        url: jarvisUrl ('__status'),

        // We received a response back from the server, that's a good start.
        success: function (response, request_options) {
            try {
                var result = Ext.util.JSON.decode (response.responseText);
                if (result.logged_in == 0) {
                    document.location.href = login_page + '?from=' + escape (location.pathname + location.hash);
                }

            // Well, something bad here.  Could be anything.  We tried.
            } catch (e) {
                // Do nothing further.
            }
        }
    });
};

// Common submit method (does delete/update/insert).
//
//      transaction_type - 'delete', 'update', 'insert'
//      store            - The store to update.
//      dataset_name     - Name of the .xml file containing dataset config.
//      record           - The Ext.data.Record structure holding data.
//
// When the update attempt is over we will fire the store's 'writeback' listener with arguments
//
//      store        - This store.
//      result       - object containing attributes:
//                          success: (Mandatory) 1 (succeeded), 0 (failed)
//                          message: (Optional) Error message text, present if update failed.
//                          data:    (Optional) Array of returned objects.  E.g. if SQL used INSERT RETURNING.
//
//      transaction_type - 'update', 'insert' or 'delete' as supplied for request
//      records          - Record(s) to send.  May be hash (1 record) or array of hashes.
//      num_pending      - Number of remaining changes still queued.
//
function jarvisSendChange (transaction_type, store, dataset_name, records) {

    // Fields is a copy of "record.data" that we extend with some extra magic attributes:
    //
    //     _operation_type: (Mandatory) 'update' or 'delete'
    //     _record_id:      (Mandatory) Internal ExtJS Store ID.
    //
    // Note that _record_id is the INTERNAL ExtJS ID.  Not the database "id" column.
    //
    var fields = [];

    // Is it an array?
    if (typeof records.length === 'number') {
        for (var i = 0; i < records.length; i++) {
            fields.push (records[i].data);
            fields[i]._record_id = records[i].id;
        }

    // Or just a single record.
    } else {
        fields = records.data;
        fields._record_id = records.id;
    }

    // Convert to standards.
    var request_method;
    if (transaction_type == 'insert') {
        request_method = 'POST';

    } else if (transaction_type == 'update') {
        request_method = 'PUT';

    } else if (transaction_type == 'delete') {
        request_method = 'DELETE';

    } else {
        request_method = transaction_type;
    }

    // This is for pre-RESTful Jarvis.
    //
    // fields._transaction_type = transaction_type;

    // One more request to track in our counter.
    num_pending++;

    // Perform the request over ajax.
    Ext.Ajax.request({
        url: jarvisUrl (dataset_name),
        method: request_method,

        // We received a response back from the server, that's a good start.
        success: function (response, request_options) {
            num_pending--;   // One less request.
            // Eval the response.  It SHOULD be valid JSON.  However, bad JSON is basically
            // treated the same as good JSON with a failure flag.
            var result;
            try {
                result = Ext.util.JSON.decode (response.responseText);

            // Response wasn't good JSON.  Assume it was an error message of some kind.
            } catch (e) {
                result = new Object ();
                result.success = 0;
                result.message = 'Bad JSON: ' + response.responseText;
            }
            var listener = (typeof records.length === 'number') ? 'writebackarray' : 'writeback';
            store.fireEvent (listener, store, result, transaction_type, records, num_pending);
        },

        // Total failure.  Script failed.  It might have managed to update
        // our changes, but we have no way to tell.  You should reload your store.
        failure: function (response, request_options) {
            num_pending--;   // One less request.

            var result = new Object ();
            result.success = 0;
            result.message = 'Server responded with error.  Updates lost.';
            var listener = (typeof records.length === 'number') ? 'writebackarray' : 'writeback';
            store.fireEvent (listener, store, result, transaction_type, records, num_pending);
        },

        // Send data in the body.
        jsonData: Ext.util.JSON.encode (fields)
    });
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

// Say if our comma-separated groups list contains a nominated group.
function jarvisInGroup (wanted, group_list) {
    var group_array = group_list.split (',');
    for (i=0; i<group_array.length; i++) {
        if (group_array[i] == wanted) {
            return true;
        }
    }
    return false;
}

