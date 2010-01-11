/**
 * Description: Provides a simple API for dealing with time ranges.
 *              Date ranges are defined in a simple string format
 *              and parsed. 
 *
 *              Note that further functions may be added to this API
 *              depending on the needs of the application over time.
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

Ext.ns('jarvis');

/**
 * Create a timeframe, supports building a timeframe 
 * with a format:
 *      [n].{1-5}(now|tonight|tomorrow|lastnight)
 *
 * E.g.
 *      2..now     - two days, until this very moment.
 *      2..tonight - yesterday and today.
 *      1.now      - the last hour.
 *
 * String formats:
 *
 *      "."     == hour
 *      ".."    == day
 *      "..."   == week
 *      "...."  == month
 *      "....." == year
 *
 * Dots can be predicated by a number to indicate number of
 * that timeframe - e.g. 3.. == 3 days.
 *
 * Indicator of end/start period
 *      "now"   == now
 *      "tonight" == 12am tomorrow
 *
 * A Date object can be passed in as the second parameter
 * to indicate the 'now' time (instead of the code assuming
 * the value of 'new Date()' is now).
 */
jarvis.Timeframe = function (tf, now) {
    this._tf = tf;
    this._now = now;

    var re = this.timeframeParserRe;
    var pretendNow = now ? now.clone() : new Date();
    var s = tf.match(re);

    if (s == null) {
        throw "jarvis.Timeframe: cannot parse: " + tf;
    }

    switch (s[3]) {
        case "tonight":
            this._to = pretendNow.clearTime().add(Date.DAY, 1); break;
        case "now":
            this._to = pretendNow; break;
        default:
            throw "jarvis.Timeframe: Parse error of '" + tf + "'";
    }

    var multiplier = 1;
    if (s[1].length > 0) {
        multiplier = parseInt(s[1]);
    }

    switch (s[2].length) {
        case 1:
            this._from = this._to.clone().add(Date.HOUR, -1 * multiplier); break;
        case 2:
            this._from = this._to.clone().add(Date.DAY, -1 * multiplier); break;
        case 3:
            this._from = this._to.clone().add(Date.DAY, -7 * multiplier); break;
        case 4:
            this._from = this._to.clone().add(Date.MONTH, -1 * multiplier); break;
        case 5:
            this._from = this._to.clone().add(Date.YEAR, -1 * multiplier); break;
            
        default:
            throw "jarvis.Timeframe: Parse error of '" + tf + "'";
    }
}

/**
 * The regular expression for parsing the timeframe string.
 */
jarvis.Timeframe.prototype.timeframeParserRe = new RegExp ("^([0-9]*)([.]+)([a-z]+)$");

/**
 * Accessor functions for accessing the start/end datetimes of the
 * timeframe.
 */
jarvis.Timeframe.prototype.from = function () {
    return this._from;
}

jarvis.Timeframe.prototype.to = function () {
    return this._to;
}

/**
 * Clones the timeframe object, allowing callers to manipulate the timeframe
 * without affecting the original object.
 * 
 * Note that this function assumes the original timeframe and start date
 * used to create this Timeframe object still define the timeframe
 * correctly.
 */
jarvis.Timeframe.prototype.clone = function () {
    return new jarvis.Timeframe(this._tf, this._now);
}

/**
 * Provides the span of time for the timeframe in minutes.
 */
jarvis.Timeframe.prototype.span = function () {
    return (this._to - this._from) / (60 * 1000.0);
}

/**
 * Returns a string that defines the actual timeframe (from/to datetimes)
 */
jarvis.Timeframe.prototype.toString = function () {
    return this._from.toString() + " - " + this._to.toString();
}

