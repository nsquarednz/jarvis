//----------------------------------------------------------------------
// Common functions used by nearly all SpiderFan Edit Pages.
//----------------------------------------------------------------------

//----------------------------------------------------------------------
//----------------------------------------------------------------------
//                              HELP SYSTEM
//----------------------------------------------------------------------
//----------------------------------------------------------------------
// Our help variables.
var help_window = null;
var help_title = 'Help';
var help_filename = null;
var help_tabs = null;

// Call this before invoking help.
function helpInit (filename, title, tabs) {
    help_filename = filename;   // Mandatory.
    help_title = title;         // Recommended.
    help_tabs = tabs;           // Only for tabbed screens.
}

// Loads help for just one window, i.e. non-tabbed.  Either use default
// filename from helpInit (), or specify one ourselves.
//
function helpShow (override_filename) {
    var filename = override_filename || help_filename;
    if (! filename) { return; }

    var help_url = 'help/' + filename + '.html';
    if (help_window == null) {
        help_window = new Ext.Window ({
            title: help_title,
            autoLoad: help_url,
            autoScroll: true,
            closeAction: 'hide',
            width: 460,
            height: 600
        });
    }
    help_window.setVisible (true);
}

// Load our help for current tab.  If window is not created, may create/display it,
// or may not.  You decide.
function helpShowTab (show) {
    if (! help_filename) { return; }
    if (! help_tabs) { return; }

    if (! show && ! (help_window && help_window.isVisible())) {
        return;
    }
    var active_tab_number = help_tabs.items.indexOf (help_tabs.getActiveTab());
    var help_url = '/edit/help/' + help_filename + '_tab' + active_tab_number + '.html';

    if (help_window != null) {
        help_window.load ({ 'url': help_url});

    } else {
        help_window = new Ext.Window ({
            title: help_title,
            autoLoad: help_url,
            autoScroll: true,
            closeAction: 'hide',
            width: 400,
            height: 520,
            items: new Ext.Panel ()
        });
    }
    show && help_window.setVisible (true);
}

//----------------------------------------------------------------------
//----------------------------------------------------------------------
//                              VTYPES for EXTJS
//----------------------------------------------------------------------
//----------------------------------------------------------------------

Ext.apply(Ext.form.VTypes, {
    // Floating point number, +ve or -ve.
    'numeric': function() {
        var numericRe = /(^\-?\d\d*\.\d*$)|(^\-?\d\d*$)|(^\-?\.\d\d*$)/;
        return function(v) { return numericRe.test(v); }
    }(),
    'numericText' : 'Not a valid numeric number. Must be digits only.',
    'numericMask' : /[\-\.0-9]/,

    // Positive integer.
    'positivenum': function() {
        var numericRe = /^\d+$/;
        return function(v) { return numericRe.test(v); }
    }(),
    'positivenumText' : 'Not a valid numeric number. Must be digits only.',
    'positivenumMask' : /[0-9]/,

    // a-zA-Z0-9 including empty
    'alphanum': function() {
        var numericRe = /^[a-zA-Z0-9]*$/;
        return function(v) { return numericRe.test(v); }
    }(),
    'alphanumText' : 'Not a valid alphanumeric.  a-z, A-Z, 0-9 only.',
    'alphanumMask' : /[a-zA-Z0-9]/,

    // A-Z0-9 including empty
    'upperalphanum': function() {
        var numericRe = /^[A-Z0-9]*$/;
        return function(v) { return numericRe.test(v); }
    }(),
    'upperalphanumText' : 'Not a valid uppercase alphanumeric.  A-Z, 0-9 only.',
    'upperalphanumMask' : /[A-Z0-9]/
});

//----------------------------------------------------------------------
//----------------------------------------------------------------------
//                              RENDER METHODS
//----------------------------------------------------------------------
//----------------------------------------------------------------------

// This contains handy functions for rendering things.  Mostly it's grid cells
// we want to custom render, and mostly we want them to render "red" when we
// don't like the data contained.  Note that because of the way the grid cell
// template works, we can't easily add a class to the inner cell, but we can do
// it via a style tag.  This means that the colors hard-coded here need to match
// your CCS file.  That's not ideal, but it gives the best result I can find in
// terms of visual effect.
//
var style_invalid = 'style="border: solid 1px #DD7870; padding-bottom: 2"';

// This is a renderer which adds a red border around empty string grid cells.
renderRequireNonEmpty = function (val, md, rec, rowIndex, colIndex, ds) {
    (val && (val.length > 0)) || (md.attr = style_invalid);
    return val;
}

renderRequirePositiveInt = function (val, md, rec, rowIndex, colIndex, ds) {
    (val && (val > 0)) || (md.attr = style_invalid);
    return val;
}

renderRequirePositiveZeroInt = function (val, md, rec, rowIndex, colIndex, ds) {
    val = val || 0;
    (val >= 0) || (md.attr = style_bad);
    return val;
}

renderCheckbox = function (value, md, rec, rowIndex, colIndex, ds) {
    return '<img class="x-grid-checkbox" src="/ext-2.3/resources/images/default/menu/'
        + ((value && (value != 0)) ? 'checked.gif' : 'unchecked.gif') + '"/>';
};

renderZeroAsBlank = function (val, md, rec, rowIndex, colIndex, ds) {
    return (val && (val > 0)) ? val : '';
}

//----------------------------------------------------------------------
//----------------------------------------------------------------------
//                              EXTJS OVERRIDES
//----------------------------------------------------------------------
//----------------------------------------------------------------------

//-------------------------------------------------------------------------
// Override the checkbox for... some reason that I forget.  Possibly to fix
// a bug I think.  Yeah, probably that's why.
//-------------------------------------------------------------------------
Ext.override(Ext.form.Checkbox, {
    getValue : function(){
        if(this.rendered){
            return this.el.dom.checked;
        }
        return this.checked;
    },

    setValue : function(v) {
        var checked = this.checked;
        this.checked = (v === true || v === 'true' || v == '1' || String(v).toLowerCase() == 'on');

        if(this.rendered){
            this.el.dom.checked = this.checked;
            this.el.dom.defaultChecked = this.checked;
            this.wrap[this.checked? 'addClass' : 'removeClass'](this.checkedCls);
        }

        if(checked != this.checked){
            this.fireEvent("check", this, this.checked);
            if(this.handler){
                this.handler.call(this.scope || this, this, this.checked);
            }
        }
    }
});

//-------------------------------------------------------------------------
// Change GridView focusRow to allow us to temporarily suspend autoFocus
// of a row.  This is particularly when we are moving or modifying lots
// of rows at once, e.g. when shuffling rows.
//-------------------------------------------------------------------------
Ext.override (Ext.grid.GridView, {
    focusRow : function(row){
        if (this.suspendFocus) { return }
        this.focusCell(row, 0, false);
    }
});

//-------------------------------------------------------------------------
// Empty element in combo box displayed as &nbsp;
//-------------------------------------------------------------------------
Ext.override(Ext.form.ComboBox, {
    initList: (function(){
        if(!this.tpl) {
            this.tpl = new Ext.XTemplate('<tpl for="."><div class="x-combo-list-item">{', this.displayField , ':this.blank}</div></tpl>', {
                blank: function(value) {
                    return value==='' ? '&nbsp' : value;
                }
            });
        }
    }).createSequence(Ext.form.ComboBox.prototype.initList)
});

//-------------------------------------------------------------------------
// Enhance Store to have a method which will callback so that we can write each
// modified record, without actually finalising the commit until later.
//-------------------------------------------------------------------------
Ext.override (Ext.data.Store, {
    /**
     * Fires the update event with "WRITE" as the parameter.  Does NOT COMMIT
     * ANY CHANGES.  When you receive your Ajax response(s), then for each record
     * successfully written, you simply call <record>.commit() to finalise
     * the change in the local store and grid.
     */
    writeChanges : function (){
        var m = this.modified.slice (0);
        for (var i = 0, len = m.length; i < len; i++){
            this.fireEvent("write", this, m[i]);
        }
    },

    /**
     * Similar to "write", but fires a single event with an array of all modified
     * records.
     */
    writeArrayChanges : function (){
        var m = this.modified.slice (0);
        if (m.length > 0) {
            this.fireEvent("writearray", this, m);
        }
    },

    /**
     * Call this when you get your writebackarray callback.  We'll commit all the
     * changes that worked, and error those that didn't.  We'll also handle "returning"
     * as long as you returned a '_record_id' field.
     */
    handleWriteback : function (result, ttype, record, remain) {
        if (result.success != 1) {
            alert (result.message);
            return 0;

        } else {
            if (result.returning != null) {
                for (var j = 0; j < result.returning.length; j++) {
                    var r = this.getById (result.returning[j]._record_id);
                    for (var key in result.returning[j]) {
                        if (key != '_record_id') {
                            r.data[key] = result.returning[j][key];
                        }
                    }
                }
            }
            if (ttype == 'delete') {
                this.remove (record);
            } else {
                record.commit ();
            }
            return 1;
        }
    },

    /**
     * Call this when you get your writebackarray callback.  We'll commit all the
     * changes that worked, and error those that didn't.  We'll also handle "returning"
     * as long as you returned a '_record_id' field.
     */
    handleWritebackArray : function (result, ttype, records, remain) {
        if (result.success != 1) {
            alert (result.message);
            return 0;

        } else {
            if (result.row != null) {
                for (var i = 0; i < result.row.length; i++) {
                    if (result.row[i].success) {
                        if (result.row[i].returning != null) {
                            for (var j = 0; j < result.row[i].returning.length; j++) {
                                var r = this.getById (result.row[i].returning[j]._record_id);
                                for (var key in result.row[i].returning[j]) {
                                    if (key != '_record_id') {
                                        r.data[key] = result.row[i].returning[j][key];
                                    }
                                }
                            }
                        }
                        if (records[i].data._ttype == 'delete') {
                            this.remove (records[i]);
                        } else {
                            records[i].commit ();
                        }
                    }
                }
            }
            return 1;
        }
    }
});
