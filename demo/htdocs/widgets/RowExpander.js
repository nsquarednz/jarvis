/*
 * Ext JS Library 2.2
 * Copyright(c) 2006-2008, Ext JS, LLC.
 * licensing@extjs.com
 *
 * http://extjs.com/license
 */
Ext.grid.RowExpander = function(config){
    Ext.apply(this, config);

    this.addEvents({
        beforeexpand : true,
        expand: true,
        beforecollapse: true,
        collapse: true
    });

    Ext.grid.RowExpander.superclass.constructor.call(this);

    this.state = {};
};

Ext.extend(Ext.grid.RowExpander, Ext.util.Observable, {
    header: "",
    width: 20,
    sortable: false,
    fixed:true,
    menuDisabled:true,
    dataIndex: '',
    id: 'expander',
    lazyRender : true,
    displayHtmlVerbatim: true,
    dataFieldName: 'description',

    // This is called when the row is first created.  It is also called when the
    // data value is updated by the editor.
    //
    //  record      - record for this row.
    //  rowIndex    - integer row index for this row
    //  p           - A "RowParams"object, used within GridView.js to build the row
    //                via the "row" template defined in that file.
    //  ds          - Grid's data store object.
    //
    getRowClass : function(record, rowIndex, p, ds){
        p.cols = p.cols-1;

        if(this.state[record.id] || !this.lazyRender){
            content = this.getWrappedBodyContent(record, rowIndex);
            p.body = content;
        }

        // This sets the style attribute of the TR.  Not very useful.  We need the contained cell.
        return this.state[record.id] ? 'x-grid3-row-expanded' : 'x-grid3-row-collapsed';
    },

    init : function(grid){
        this.grid = grid;

        var view = grid.getView();
        view.getRowClass = this.getRowClass.createDelegate(this);

        view.enableRowBody = true;

        grid.on('render', function(){
            view.mainBody.on('mousedown', this.onMouseDown, this);
        }, this);
    },

    // This returns the content for the second row, which is used as follows.
    //
    // <tr class="x-grid3-row-body-tr" style="">
    //   <td class="x-grid3-body-cell" hidefocus="on" tabindex="0" colspan="5">
    //     <div class="x-grid3-row-body">
    //       --Text/HTML content returned from getBodyContent goes here --
    //     </div>
    //   </td>
    // </tr>
    getBodyContent : function (record, index){
        var content = record.get (this.dataFieldName);
        if (content && this.displayHtmlVerbatim) {
            content = content.replace (/\</g, '&lt;')
            content = content.replace (/\>/g, '&gt;')
        }
        return content;
    },

    // Wraps the input in a couple of divs.
    getWrappedBodyContent : function (record, index){
        var content = this.getBodyContent (record, index);
        if (content) {
            content = '<div class="x-grid3-padded-cell">' + content + '</div>';
            if (record.dirty && (typeof record.modified['intro'] != 'undefined')) {
                content = '<div class="x-grid3-dirty-cell">' + content + '</div>';
            }
        }
        return content;
    },

    onMouseDown : function(e, t){
        if(t.className == 'x-grid3-row-expander'){
            e.stopEvent();
            var row = e.getTarget('.x-grid3-row');
            this.toggleRow(row);
        }
    },

    // This renders the expander button, not the actual row body.
    renderer : function(v, p, record){
        p.cellAttr = 'rowspan="2"';
        return '<div class="x-grid3-row-expander">&#160;</div>';
    },

    beforeExpand : function(record, body, rowIndex){
        return this.fireEvent('beforeexpand', this, record, body, rowIndex);
    },

    toggleRow : function(row){
        if(typeof row == 'number'){
            row = this.grid.view.getRow(row);
        }
        this[Ext.fly(row).hasClass('x-grid3-row-collapsed') ? 'expandRow' : 'collapseRow'](row);
    },

    expandRow : function(row){
        if(typeof row == 'number'){
            row = this.grid.view.getRow(row);
        }
        var record = this.grid.store.getAt(row.rowIndex);
        var body = Ext.DomQuery.selectNode('tr:nth(2) div.x-grid3-row-body', row);
        if(this.beforeExpand(record, body, row.rowIndex)){
            this.state[record.id] = true;
            Ext.fly(row).replaceClass('x-grid3-row-collapsed', 'x-grid3-row-expanded');
            this.fireEvent('expand', this, record, body, row.rowIndex);
        }
    },

    collapseRow : function(row){
        if(typeof row == 'number'){
            row = this.grid.view.getRow(row);
        }
        var record = this.grid.store.getAt(row.rowIndex);
        var body = Ext.fly(row).child('tr:nth(1) div.x-grid3-row-body', true);
        if(this.fireEvent('beforecollapse', this, record, body, row.rowIndex) !== false){
            this.state[record.id] = false;
            Ext.fly(row).replaceClass('x-grid3-row-expanded', 'x-grid3-row-collapsed');
            this.fireEvent('collapse', this, record, body, row.rowIndex);
        }
    }
});
