/**
 * Description: Simple date functions to help interact with the Jarvis
 *              system for this tracker application.
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

/**
 * Description:   Returns the julian date value for the given date object,
 *                Note that there is no need to adjust to UTC from browser 
 *                local time as the getTime() function returns a UTC value.
 *
 * Parameters:
 *      trunc   - If true truncates the returned date to midnight on 
 *                the date the time occurs.
 */
Date.prototype.getJulian = function (trunc) {
    // 2440587.5 is the julian date offset for unix epoch
    // time. 
    if (trunc) {
        return this.clearTime().getTime() / (1000 * 60 * 60 * 24) + 2440587.5; 
    } else {
        return this.getTime() / (1000 * 60 * 60 * 24) + 2440587.5; 
    }
}

/**
 * Description:   Converts a number which is considered a Julian date value
 *                into a JavaScript Date object, with the date the Julian
 *                date number represents.
 *
 *                The input value is coerced into a number.
 */
Date.fromJulian = function (jt) {
    return new Date(Math.round((jt - 2440587.5) * (1000 * 60 * 60 * 24)));
}

/**
 * Description:   Helper function added to the Date prototype to convert
 *                the date from a Date object into a string that can be sent
 *                to the server and used in queries.
 *
 *                For this application, this returns a Julian date value
 *                that represents the input Date object time.
 */
Date.prototype.formatForServer = function () {
    // ExtJS Date.format function
    var result = this.format('Y-m-d H:i:s');
    console.log('formatForServer', this, result);
    return result;
}

/**
 * Description:   Given a date object, or a time string, return a 
 *                user-friendly date such as '2 hours ago'.
 */
function prettyDate(time){
    var diff = (((new Date()).getTime() - time.getTime()) / 1000),
        day_diff = Math.floor(diff / 86400);
            
    if (isNaN(day_diff)) {
        return;
    }

    if (day_diff < 0) {
        return 'in the future';
    }
        
    if (day_diff >= 31) {
        return 'months ago';
    }

    return day_diff == 0 && (
            diff < 60 && "just now" ||
            diff < 120 && "1 minute ago" ||
            diff < 3600 && Math.floor( diff / 60 ) + " minutes ago" ||
            diff < 7200 && "1 hour ago" ||
            diff < 86400 && Math.floor( diff / 3600 ) + " hours ago") ||
        day_diff == 1 && "Yesterday" ||
        day_diff < 7 && day_diff + " days ago" ||
        day_diff < 31 && Math.ceil( day_diff / 7 ) + " weeks ago";
}

Ext.util.Format.prettyDate = function (time) {
    return prettyDate(time);
}

