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

// Common submit method (does delete/update/insert).  Needs:
//
//      store        - The store to update.
//      dataset_name - Name of the .xml file containing dataset config.
//      fields       - Copy of "record.data" that we extend with some extra magic attributes:
//                          _operation_type: (Mandatory) 'update' or 'delete'
//                          _record_id:      (Mandatory) Internal ExtJS Store ID.
//
// When the update attempt is over we will fire the store's 'writeback' listener with arguments
//      store        - This store.
//      result       - object containing attributes:
//                          success: (Mandatory) 1 (succeeded), 0 (failed)
//                          message: (Optional) Error message text, present if update failed.
//                          data:    (Optional) Array of returned objects.  E.g. if SQL used INSERT RETURNING.
//
function jarvisSendChange (store, dataset_name, fields) {
    Ext.Ajax.request({
        url: jarvis_home,

        // We received a response back from the server, that's a good start.
        success: function (response, request) {

            // Eval the response.  It SHOULD be valid JSON.  However, bad JSON is basically
            // treated the same as good JSON with a failure flag.
            var result;
            try {
                result = Ext.util.JSON.decode (response.responseText);

                // If we succeeded, fire the writeback listener if this was the last update.
                if (result.success == 1) {
                    if (store.getModifiedRecords().length == 0) {
                        store.fireEvent ('writeback', store, result);
                    }

                // This indicates that not all updates succeeded.  You should reload your store.
                } else {
                    store.fireEvent ('writeback', store, result);
                }

            // Response wasn't good JSON.  Assume it was an error message of some kind.
            } catch (e) {
                var result = new Object ();
                result.success = 0;
                result.message = response.responseText;
                store.fireEvent ('writeback', store, result);
            }
        },

        // Total failure.  Script failed.  It might have managed to update
        // our changes, but we have no way to tell.  You should reload your store.
        failure: function () {
            var result = new Object ();
            result.success = 0;
            result.message = 'Server responded with error.  Updates lost.';
            store.fireEvent ('writeback', store, result);
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
function jarvisRemove (store, dataset_name, record) {
    var fields = record.data;
    fields._record_id = record.id;          // This is the INTERNAL ExtJS ID.  Not the database "id" column.
    fields._transaction_type = 'remove';
    jarvisSendChange (store, dataset_name, fields);
}

// Transaction Type = Update.  Creates OR Updates a single row in the specified store.
function jarvisUpdate (store, dataset_name, record) {
    var fields = record.data;
    fields._record_id = record.id;          // This is the INTERNAL ExtJS ID.  Not the database "id" column.
    fields._transaction_type = 'update';    
    jarvisSendChange (store, dataset_name, fields);
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
