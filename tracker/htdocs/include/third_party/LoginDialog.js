/**
 * Free and simple to use loginDialog for ExtJS 2.x
 *
 * Altered slightly by Jamie Love (N-Squared Software) to handle the response
 * from Jarvis.
 * 
 * @author  Albert Varaksin
 * @license LGPLv3 http://www.opensource.org/licenses/lgpl-3.0.html
 * @version 1.0 beta 
 */


/*
 * Put it into it's own namespace
 */
Ext.namespace('Ext.ux.albeva');


/**
 * Login dialog constructor
 * 
 * @param {Object} config
 * @extends {Ext.util.Observable}
 */
Ext.ux.albeva.LoginDialog = function (config)
{
    Ext.apply(this, config);
    
    // The CSS needed to style the dialog.
    // For perfomance this could be in a CSS file
    var css = ".ux-albeva-auth-lock-icon {background: url('" + this.basePath + "/lock-icon.gif') 0 6px no-repeat !important;}"
            + ".ux-albeva-auth-header {background:transparent url('"+this.basePath+"/login-big.gif') no-repeat center right;padding:12px;padding-right:45px;font-weight:bold;}"
            + ".ux-albeva-auth-header .error {color:red;}"
            + ".ux-albeva-auth-form {padding:10px;}";
    Ext.util.CSS.createStyleSheet(css, this._cssId);
    
    // LoginDialog events
    this.addEvents ({
        'show'      : true, // when dialog is visible and rendered
        'cancel'    : true, // When user cancelled the login
        'success'   : true, // on succesfful login
        'failure'   : true, // on failed login
        'submit'    : true  // about to submit the data
    });
    Ext.ux.albeva.LoginDialog.superclass.constructor.call(this, config);
    
    // head info panel
    this._headPanel = new Ext.Panel ({
        baseCls : 'x-plain',
        html    : this.message,
        cls     : 'ux-albeva-auth-header',
        region  : 'north',
        height  : 50
    });
    
    // set field id's
    this.usernameId = this.usernameId || Ext.id();
    this.passwordId = this.passwordId || Ext.id();
    
    // form panel
    this._formPanel = new Ext.form.FormPanel ({
        region      : 'center',
        border      : false,
        bodyStyle   : "padding:10px;",
        labelWidth  : 75,
        defaults    : { width:170 },
        items : [
            {
                xtype       : 'textfield',
                id          : this.usernameId,
                name        : this.usernameField,
                fieldLabel  : this.usernameLabel,
                vtype       : this.usernameVtype,
                allowBlank  : false
            },
            {
                xtype       : 'textfield',
                inputType   : 'password',
                id          : this.passwordId,
                name        : this.passwordField,
                fieldLabel  : this.passwordLabel,
                vtype       : this.passwordVtype,
                allowBlank  : false
            }
        ]
    });
    
    // Default buttons and keys
    var buttons = [{
        text    : this.loginButton, 
        handler : this.submit,
        scope   : this
    }];
    var keys = [{
        key     : [10,13],
        handler : this.submit,
        scope   : this
    }];
    
    // if cancel button exists
    if (typeof this.cancelButton == 'string')
    {
        buttons.push({
            text    : this.cancelButton,
            handler : this.cancel,
            scope   : this
        });
        keys.push({
            key     : [27],
            handler : this.cancel,
            scope   : this
        });            
    }
    
    
    // create the window
    this._window = new Ext.Window ({
        width       : 290,
        height      : 200,
        closable    : false,
        resizable   : false,
        modal       : this.modal,
        iconCls     : 'ux-albeva-auth-lock-icon',
        title       : this.title,
        layout      : 'border',
        bodyStyle   : 'padding:5px;',
        buttons     : buttons,
        keys        : keys,
        items       : [this._headPanel, this._formPanel]
    });
    
    // when window is visible set focus to the username field
    // and fire "show" event
    this._window.on ('show', function () {
        Ext.getCmp(this.usernameId).focus(false, true);
        this.fireEvent('show', this);
    }, this);
};


// Extend the Observable class
Ext.extend (Ext.ux.albeva.LoginDialog, Ext.util.Observable, {
    
    /**
     * LoginDialog window title
     * 
     * @type {String}
     */
    title :'Authenticate',
    
    /**
     * The message on the LoginDialog
     * 
     * @type {String}
     */
    message : 'Login to CMS',
    
    /**
     * When login failed and no server message sent
     * 
     * @type {String}
     */
    failMessage : 'Unable to log in',

    /**
     * Error message reader - object that 
     * Ext.form.Action.Submit will use to read the response
     * from the server to decide on the success or failure of
     * the login attempt.
     */
    responseReader: null,

    /**
     * The parameter in the JSON response that provides the
     * failure message.
     */
    failMessageParameter : 'message', 
    
    /**
     * When submitting the login details
     * 
     * @type {String}
     */
    waitMessage : 'Logging in ...',
    
    /**
     * The login button text
     * 
     * @type {String}
     */
    loginButton : 'Login',
    
    /**
     * Cancel button
     * 
     * @type {String}
     */
    cancelButton : null,
    
    /**
     * Username field label
     * 
     * @type {String}
     */
    usernameLabel : 'Username',
    
    /**
     * Username field name
     * 
     * @type {String}
     */
    usernameField : 'username',
    
    /**
     * Username field id
     * 
     * @type {String}
     */
    usernameId : null,
    
    /**
     * Username validation
     * 
     * @type {String}
     */
    //usernameVtype :'alphanum',
    
    /**
     * Password field label
     * 
     * @type {String}
     */
    passwordLabel :'Password',
    
    /**
     * Passowrd field name
     * 
     * @type {String}
     */
    passwordField :'password',
    
    /**
     * Password field id
     * 
     * @type {String}
     */
    passwordId : null,
    
    /**
     * Password field validation
     * 
     * @type {String}
     */
    //passwordVtype : 'alphanum',
    
    /**
     * Request url
     * 
     * @type {String}
     */
    url : '/auth/login/',
    
    /**
     * Path to images
     * 
     * @type {String}
     */
    basePath : '/',
    
    /**
     * Form submit method
     * 
     * @type {String}
     */
    method : 'post',
    
    /**
     * Open modal window
     * 
     * @type {Bool}
     */
    modal : false,
    
    /**
     * CSS identifier
     * 
     * @type {String}
     */
    _cssId : 'ux-albeva-auth-css',
    
    /**
     * Head info panel
     * 
     * @type {Ext.Panel}
     */
    _headPanel : null,
    
    /**
     * Form panel
     * 
     * @type {Ext.form.FormPanel}
     */
    _formPanel : null,
    
    /**
     * The window object
     * 
     * @type {Ext.Window}
     */
    _window : null,
    
    
    /**
     * Set the LoginDialog message
     * 
     * @param {String} msg
     */
    setMessage : function (msg)
    {
        this._headPanel.body.update(msg);
    },
    
    
    /**
     * Show the LoginDialog
     * 
     * @param {Ext.Element} el
     */
    show : function (el)
    {
        this._window.show(el);
    },
    
    
    /**
     * Close the LoginDialog and cleanup
     */
    close : function () 
    {
        this._window.close();
        this.purgeListeners();
        Ext.util.CSS.removeStyleSheet(this._cssId);
        var self = this;
        delete self;
    },
    
    
    /**
     * Cancel the login (closes the dialog window)
     */
    cancel : function ()
    {
        if (this.fireEvent('cancel', this))
        {
            this.close();
        }
    },
    
    
    /**
     * Submit login details to the server
     */
    submit : function ()
    {
        var form = this._formPanel.getForm();
        if (form.isValid())
        {
            if (this.fireEvent('submit', this, form.getValues()))
            {
                this.setMessage (this.message);
                if (this.responseReader) 
                    form.errorReader = this.responseReader;
                form.submit ({
                    url     : this.url,
                    method  : this.method,
                    waitMsg : this.waitMessage,
                    success : this.onSuccess,
                    failure : this.onFailure,
                    scope   : this
                });
            }
        }
    },
    
    
    /**
     * On success
     * 
     * @param {Ext.form.BasicForm} form
     * @param {Ext.form.Action} action
     */
    onSuccess : function (form,action)
    {
        if (this.fireEvent('success', this, action)) this.close();
    },
    
    
    /**
     * On failures
     * 
     * @param {Ext.form.BasicForm} form
     * @param {Ext.form.Action} action
     */
    onFailure : function (form,action)
    {
        var msg = '';
        if (action.result && action.result[this.failMessageParameter]) msg = action.result[this.failMessageParameter] || this.failMessage;
        else msg = this.failMessage;
        this.setMessage (this.message + '<br /><span class="error">' + msg + '</span>');
        this.fireEvent('failure', this, action, msg);
    }
    
});
