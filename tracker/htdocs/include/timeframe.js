/**
 * Provides a simple API for dealing with time ranges
 * and time <-> pixel conversions
 */

var jarvis = jarvis ? jarvis : {};

/**
 * Create a timeframe, supports building a timeframe 
 * with a format  [n].{1-5}(now|tonight...)
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
 *      "tomorrow" == currenty time tomorrow
 *      "lastnight" == 12am today
 *
 * A Date object can be passed in as the second parameter
 * to indicate the 'now' time (instead of the code assuming
 * new Date() is now).
 */
jarvis.Timeframe = function (tf, now) {

    this._tf = tf;
    this._now = now;

    var pretendNow = now ? now.clone() : new Date();
    var re = new RegExp ("([0-9]*)([.]+)([a-z]+)"); // TODO Don't create each time.
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

jarvis.Timeframe.prototype.from = function () {
    return this._from;
}

jarvis.Timeframe.prototype.to = function () {
    return this._to;
}

/**
 * Clones the timeframe object, allowing callers to manipulate
 * it.
 */
jarvis.Timeframe.prototype.clone = function () {
    return new jarvis.Timeframe(this._tf, this._now);
}

/**
 * Provides the span of time for the timeframe in minutes.
 */
jarvis.Timeframe.prototype.span = function () {
    return (this._to - this._from) / (60 * 1000);
}

jarvis.Timeframe.prototype.toString = function () {
    return this._from.toString() + " - " + this._to.toString();
}

/**
 * Helper function added to the Date prototype. 
 */
Date.prototype.formatForServer = function () {
    return this.getJulian();
}
