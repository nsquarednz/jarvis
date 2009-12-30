/**
 * Displays dates on a visualisation. It decides how many dates to show, and
 * when to show them so that it looks good to the user, regardless of
 * number of days actually shown
 */
var jarvis = jarvis ? jarvis : {};
jarvis.graph = jarvis.graph ? jarvis.graph : {};


jarvis.graph.DateAxis = function () {
}

jarvis.graph.DateAxis.prototype.timeframe = function (t) {
    this._timeframe = t;
    return this;
}

jarvis.graph.DateAxis.prototype.size = function (w, h) {
    this._width = w;
    this._height = h;
    return this;
}

jarvis.graph.DateAxis.prototype.textStyle = function (ts) {
    this._textStyle = ts;
    return this;
}

/**
 * Align the axis to top or bottom (pass in "top", "middle" or "bottom").
 */
jarvis.graph.DateAxis.prototype.valign = function (a) {
    this._valign = a;
    return this;
}

jarvis.graph.DateAxis.prototype.offset = function (o) {
    this._offset = o;
    return this;
}

/**
 * trigger to add rules to the graph.
 */
jarvis.graph.DateAxis.prototype.rule = function () {
    this._rule = true;
    return this;
}

/**
 * Add the axis to the given protovis canvas (panel or whatever).
 */
jarvis.graph.DateAxis.prototype.addTo = function(v) {

    // Decide if we're showing values for every day, or whatever.
    // TODO - this needs to be based on each day's data width as well.
    var scale = "full-day";   // If only a few days are shown
    if (this._timeframe.span() <= 60 * 24 * 14 && this._timeframe.span() > 2 * 60 * 24) { // For about a week or 2
        scale = "short-day";
    } else if (this._timeframe.span() > 60 * 24 * 14) {
        scale = "date-only";
    }

    var numberOfDates = Math.ceil(this._timeframe.span() / (60 * 24));
    var perDateWidth = this._width / numberOfDates;

    var startDate = this._timeframe.from();

    var lastDate = null;
    var dateNameGenerator = function (d) { // TODO enclose better.
        var ld = lastDate;
        lastDate = d.clone();
        if (ld == null || ld.getMonth() != d.getMonth()) {
            if (ld == null || ld.getYear() != d.getYear()) {
                if (scale == "full-day") {
                    return d.format("l jS F Y");
                } else if (scale == "short-day") {
                    return d.format("D d M y");
                } else if (scale == "date-only") {
                    return d.format ("d/m/y");
                }
            } else {
                if (scale == "full-day") {
                    return d.format("l jS F");
                } else if (scale == "short-day") {
                    return d.format("D d M");
                } else if (scale == "date-only") {
                    return d.format ("d/m/y");
                }
            }
        } else {
            if (scale == "full-day") {
                return d.format("l jS");
            } else if (scale == "short-day") {
                return d.format("D jS");
            } else if (scale == "date-only") {
                return d.format ("d");
            }
        }
    }

    var dates = [];
    if (perDateWidth > 10) { // If there is enough room for a date each day, do it.
        var dc = numberOfDates;
        var d = startDate.clone();
        var skip = 0;
        while (dc--) {
            var label = skip ? "" : dateNameGenerator(d)

            if (!skip) {
                skip = label.length * 5 > perDateWidth ? Math.ceil(label.length * 5 / perDateWidth) - 1: 0; // 4 pixels per character
                if (skip > dc) {
                    label =  dateNameGenerator(d); // Try again with date - this'll force the short version of the date.
                    skip = label.length * 5 > perDateWidth ? Math.ceil(label.length * 5 / perDateWidth) - 1: 0; // 4 pixels per character
                    if (skip > dc) { // If still to long, don't include
                        label = "";
                    }
                }

            } else {
                skip--;
            }

            dates.push({label: label, left: (numberOfDates - dc - 1) * perDateWidth});
            d = d.add(Date.DAY, 1);
        }
    } else { // If there is not enough room for a date each day, do one every sunday
        var dc = numberOfDates;
        var d = startDate.clone();
        var skip = 0;
        while (dc--) {
            if (skip == 0 && (dc == numberOfDates - 1 || d.getDay() == 0)) {
                var label = dateNameGenerator(d);
                skip = label.length * 5 > perDateWidth ? Math.ceil(label.length * 5 / perDateWidth): 0; // 4 pixels per character

                if (skip > dc) { // If still to long, don't include
                    label = "";
                }
            } else {
                label = "";
            }
            if (label.length > 0) {
                dates.push({label: label, left: (numberOfDates - dc - 1) * perDateWidth});
            }
            d = d.add(Date.DAY, 1);
            skip = skip != 0 ? skip - 1 : 0;
        }
    }

    if (this._rule) {
        // If there is room ( more than 10 pixels per day, add a midday line in).
        var expandedDates = reduce (function (x, y) {
            x.push(y);
            x.push ({label: "", left: y.left + perDateWidth / 2});
            return x;
        }, [], dates);
        
        v.add (pv.Rule)
            .data (expandedDates)
            .left (function (d) { return d.left })
            .top(function (d) { return (this.index % 2 == 1 ? 15 : 5) })
            .bottom (0)
            .strokeStyle(function(d) { return (this.index % 2 == 1 ? "#f3f3f3" : "#999") })
            .anchor("top").add (pv.Label)
            .textStyle (this._textStyle ? this._textStyle : "#999")
            .textAlign ("left")
            .text (function (d) { return d.label });
    } else {
        var labels = v.add (pv.Label)
            .data (dates)
            .left (function (d) { return d.left } )
            .textStyle (this._textStyle ? this._textStyle : "#999")
            .textAlign("left")
            .text(function (d) { return d.label })

        if (!this._valign || this._valign == "top") {
            labels.top (this._offset ? this._offset : 0).textBaseline ("top");
        } else if (this._valign == "bottom") {
            labels.bottom (this._offset ? this._offset : 0).textBaseline ("bottom");
        }

    }

    return this;
}
