/**
 * Description: Helper functions to manage interactions with Jarvis - including
 *              managing login requirements.
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

Ext.ns ('jarvis.tracker');

/**
 * This function is a 'loadexception' handler for Ext stores that use a HTTP proxy
 * for accessing Jarvis. The handler will ignore 401 errors (as they're covered by
 * the global handler that looks for the need to login) but on other errors will show
 * an ExtJS message box with the error that has occurred.
 */
jarvis.tracker.extStoreLoadExceptionHandler = function (proxy, options, response, e) {
    if (response.status != 401) { // 401 == unauthorised.
        if (e) {
            Ext.Msg.show ({
                title: 'Data Parsing Error',
                msg: 'Cannot understand data from server: ' + e,
                buttons: Ext.Msg.OK,
                icon: Ext.Msg.ERROR
            });
        } else {
            Ext.Msg.show ({
                title: 'Data Retrieval Error',
                msg: '<b>Cannot load:</b> ' + options.url + '<br><b>Received:</b> ' + response.responseText,
                buttons: Ext.Msg.OK,
                icon: Ext.Msg.ERROR
            });
        }
    }
};

/**
 * This function is a 'failure' handler for Ext.Ajax.request calls.
 * The handler will ignore 401 errors (as they're covered by
 * the global handler that looks for the need to login) but on other errors will show
 * an ExtJS message box with the error that has occurred.
 */
jarvis.tracker.extAjaxRequestFailureHandler = function (response, options) {
    if (response.status != 401) { // 401 == unauthorised.
        Ext.Msg.show ({
            title: 'Data Retrieval Error',
            msg: '<b>Cannot load:</b> ' + options.url + '<br><b>Received:</b> ' + response.responseText,
            buttons: Ext.Msg.OK,
            icon: Ext.Msg.ERROR
        });
    }
};

/**
 * Login function - logs the user in to the server.
 *
 * To make this work, add the following to your startup code:
 
    Ext.Ajax.on ('requestexception', function (conn, response, options) {
        if (response.status == 401) { // 401 == unauthorized and means we should try and log in.
            jarvis.tracker.login (options);
        } 
    });
 * 
 * Parameters:
 *   callbackOrRequest - Either a function to call after login is successfully completed.
 *                       or an object which is a configuration object to be passed to
 *                       a new Ext.Ajax.request() call once login is successfully completed.
 *
 * If a login is already occuring, the system stores the callbackOrRequest until the
 * login is completed.
 * 
 * There is a corner case where the logic of this function will require the user to login
 * twice. If an AJAX request 'A' is sent by the system before the successful login result has
 * been returned to the client (and the login cookie stored in the client), and then the result
 * of 'A' comes back after the successful login result has been received, this code will
 * request the user to log in again.
 *
 * I can only imagine this happening if there is a re-occuring AJAX request that happens to
 * be sent about the same time as the login request (with the username/password the user types in)
 * is sent. This is probably a < 500ms time period (unless the connection to the server is
 * extremely poor). If this becomes a problem, then we can implement fixes, with an increase
 * in complexity (one approach would be to check for login via a __status request before requesting
 * login details, and if the result came be ok, resend the request).
 */
jarvis.tracker.login = function (callback) {
    var doLogin = function () {
        var d = new Ext.ux.albeva.LoginDialog({
            url : jarvisUrl('__status'), 
            basePath : 'include/third_party',
            message: 'Login to the Jarvis Tracker',
            failMessageParameter: 'error_string',
            modal: true,
            responseReader: { // A very trivial implementation of a Reader that only has a read interface 
                           // method to identify success or failure of the login.
                read: function (response) {
                    try {
                        var d = Ext.decode (response.responseText);
                        return {
                            success: d.logged_in == '1' && d.error_string.length == 0
                        }
                    } catch (err) { // If not JSON return false - error occurred!
                        return {
                            success: false
                        }
                    }
                }
            },
            listeners: {
                success: function () { // After successful login, call callback to hopefully
                                       // rerun the request.
                    jarvis.tracker.login.postLoginActions.forEach (function (c) {
                        console.log (c);
                        if (typeof c === 'function') {
                            c();
                        } else {
                            Ext.Ajax.request(c);
                        }
                    });
                    jarvis.tracker.login.loggingIn = false;
                    jarvis.tracker.login.postLoginActions = [];
                }
            }
        });

        d.show();
    }

    // If we're currently logging in, add the request/callback to the list of things to do
    // once logged in.
    if (jarvis.tracker.login.loggingIn) {
        jarvis.tracker.login.postLoginActions.push (callback);
    } else {
        // If not yet logging in, start off.
        jarvis.tracker.login.loggingIn = true;
        jarvis.tracker.login.postLoginActions = [callback];
        doLogin();
    }
};


