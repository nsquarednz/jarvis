###############################################################################
# Description:  The Config::Setup method will read variables from our
#               <app_name>.xml (and possibly other sources).  It will perform
#               a Login attempt if required, and will set other variables
#               based on the results of the Login.  The derived config is
#               stored in an %args hash so that other functions can access
#               it.
#
#               The actual login functionality is contained in a login module,
#               e.g. Database, None, LDAP, etc.  The <app_name>.xml tells this
#               Config function which module to use for this application.
#
# Licence:
#       This file is part of the Jarvis WebApp/Database gateway utility.
#
#       Jarvis is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 3 of the License, or
#       (at your option) any later version.
#
#       Jarvis is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
#
#       This software is Copyright 2008 by Jonathan Couper-Smartt.
###############################################################################
#
use strict;
use warnings;

use CGI;
use CGI::Session;
use DBI;
use XML::Smart;

package Jarvis::Config;

use Jarvis::Error;

my %yes_value = ('yes' => 1, 'true' => 1, '1' => 1);

################################################################################
# Setup our entire jarvis config, based on the root directory passed in.
#
# Params:
#       $args_href - Reference to our args.
#
#   You Must SPECIFY
#           $args{'cgi'}                CGI object as passed in.
#           $args{'app_name'}           App name as passed in.
#           $args{'etc_dir'}            e.g. "/opt/jarvis/etc" finds our <app_name>.xml
#
#   We will ADD
#           $args{'format'}             Format xml or json?
#           $args{'use_placeholders'}   Does this app use placeholders for SQL substitution?
#           $args{'debug'}              Debug enabled for this app?
#           $args{'max_rows'}           Value for {{max_rows}}
#           $args{'dbconnect'}          Database connection string
#           $args{'dbuser'}             Database username
#           $args{'dbpass'}             Database password
#           $args{'sname'}              Session name for/from cookie.
#           $args{'sid'}                Session ID for/from cookie.
#           $args{'logged_in'}          Did a user log in?
#           $args{'username'}          Which user logged in?
#           $args{'error_string'}       What error if not logged in?
#           $args{'group_list'}         Comma-separated group list.
#           $args{'dataset_dir'}        Our dataset directory for this application.
#           $args{'exec'}               Optional hash of exec <action-name> to additional parameters:
#               -> {'command'}              Shell command to run.
#               -> {'add_headers'}          0/1 should we add headers, or will script do it?
#               -> {'filename_arg'}         A special input parameter we should use as filename.
#
# Returns:
#       1
################################################################################
#
sub Setup {
    my ($args_href) = @_;

    # Check our mandatory params
    $$args_href{'cgi'} || die "Missing parameter 'cgi'\n";
    $$args_href{'app_name'} || die "Missing parameter 'app_name'\n";
    $$args_href{'etc_dir'} || die "Missing parameter 'etc_dir'\n";

    # Check our parameters for correctness.
    ($$args_href{'app_name'} =~ m/^\w+$/) || die "Invalid characters in parameter 'app_name'.\n";
    (-d $$args_href{'etc_dir'}) || die "Parameter 'etc_dir' does not specify a directory.\n";

    ###############################################################################
    # Load our global configuration.
    ###############################################################################
    #
    # Process the global XML config file.
    my $gxml_filename = $$args_href{'etc_dir'} . "/" . $$args_href{'app_name'} . ".xml";
    my $gxml = XML::Smart->new ("$gxml_filename") || die "Cannot read '$gxml_filename': $!\n";
    ($gxml->{jarvis}) || die "Missing <jarvis> tag in '$gxml_filename'!\n";

    ###############################################################################
    # Get the application config.  Note that we must NOT store this in our args
    # hashref because XML::Smart->DESTROY gets confused if it attempts to clean up
    # XML::Smart objects at different points in the tree.
    #
    # This function should fetch all the application config at one time.
    ###############################################################################
    #
    # We MUST have an entry for this application in our config.
    my $axml = $gxml->{jarvis}{app};
    (defined $axml) || die "Cannot find <jarvis><app> in '" . $$args_href{'app_name'} . ".xml'!\n";

    # And this MUST contain our dataset dir.
    my $dataset_dir = $axml->{'dataset_dir'}->content || die "No attribute 'dataset_dir' defined for <app> in '" . $$args_href{'app_name'} . ".xml'!\n";
    $$args_href{'dataset_dir'} = $dataset_dir;
    &Jarvis::Error::Debug ("Dataset Directory '$dataset_dir'.", %$args_href);


    ###############################################################################
    # See if we have any extra "exec" actions for this application.
    ###############################################################################
    #
    my %execs = ();
    if ($axml->{'exec'}) {
        foreach my $exec (@{ $axml->{'exec'} }) {
            my $action = $exec->{'action'}->content;

            $action || die "No attribute 'action' designed for <app><exec> in '" . $$args_href{'app_name'} . ".xml'!\n";
            $exec->{'access'}->content || die "No attribute 'access' designed for <app><exec> in '" . $$args_href{'app_name'} . ".xml'!\n";
            $exec->{'command'}->content || die "No attribute 'command' designed for <app><exec> in '" . $$args_href{'app_name'} . ".xml'!\n";

            $execs {$action}{'access'} = $exec->{'access'}->content;
            $execs {$action}{'command'} = $exec->{'command'}->content;
            $execs {$action}{'add_headers'} = defined ($yes_value {lc ($exec->{'add_headers'}->content || "no")});
            $execs {$action}{'filename_parameter'} = $exec->{'filename_parameter'}->content;

            &Jarvis::Error::Debug ("Installed custom <exec> action '$action'.", %$args_href);
        }
    }
    $$args_href{'exec'} = \%execs;

    ###############################################################################
    # Determine some other application flags.
    ###############################################################################
    #
    $$args_href{'format'} = lc ($$args_href{'cgi'}->param ('format') || $axml->{'format'}->content || "json");
    (($$args_href{'format'} eq "json") || ($$args_href{'format'} eq "xml")) || die "Unsupported format '$$args_href{'format'}'!\n";

    $$args_href{'use_placeholders'} = defined ($yes_value {lc ($axml->{'use_placeholders'}->content || "no")});
    $$args_href{'debug'} = defined ($yes_value {lc ($axml->{'debug'}->content || "no")});
    $$args_href{'max_rows'} = lc ($axml->{'max_rows'}->content || 200);

    ###############################################################################
    # Connect to the database.  We'd love to cache these connections.  Need to
    # do this early, since the login module can check logins against DB table.
    ###############################################################################
    #
    my $dbxml = $axml->{'database'};
    if ($dbxml) {
        $$args_href{'dbconnect'} = $dbxml->{'connect'}->content || "dbi:Pg:" . $$args_href{'app_name'};
        $$args_href{'dbusername'} = $dbxml->{'username'}->content;
        $$args_href{'dbpassword'} = $dbxml->{'password'}->content;
    }

    ###############################################################################
    # Login Process.  Happens after DB, 'cos login info can be in DB.
    ###############################################################################
    #
    my $login_module = $axml->{login}{module} || die "Application '" . $$args_href{'app_name'} . "' has no defined login module.\n";

    eval "require $login_module";
    if ($@) {
        die "Cannot load login module '$login_module': " . $@;
    }

    # Where are our sessions stored?
    my $sid_store = $axml->{'sessiondb'}->{'store'}->content || "driver:file;serializer:default;id:md5";
    &Jarvis::Error::Debug ("SID Store '$sid_store'.", %$args_href);

    my %sid_params = ();
    if ($axml->{'sessiondb'}->{'parameter'}) {
        foreach my $sid_param (@{ $axml->{'sessiondb'}->{'parameter'} }) {
            $sid_params {$sid_param->{'name'}->content} = $sid_param->{'value'}->content;
        }
    }

    # Get an existing/new session.
    my $session = new CGI::Session ($sid_store, $$args_href{'cgi'}, \%sid_params);
    $$args_href{'sname'} = $session->name();
    $$args_href{'sid'} = $session->id();

    # By default these values are all empty.  Note that we never allow username
    # and group_list to be undef, too many things depend on it having some value,
    # even if that is just ''.
    # 
    my ($error_string, $username, $group_list, $logged_in) = ('', '', '', 0);

    # Existing, successful session?  Fine, we trust this.
    if ($session->param('logged_in') && $session->param('username')) {
        &Jarvis::Error::Debug ("Already logged in for session '" . $$args_href{'sid'} . "'.", %$args_href);
        $logged_in = $session->param('logged_in') || 0;
        $username = $session->param('username') || '';
        $group_list = $session->param('group_list') || '';

    # No successful session?  Login.  Note that we store failed sessions too.
    # 
    # Note that not all actions allow you to provide a username and password for
    # login purposes.  "status" does, and so does "fetch".  But the others don't.
    # For exec scripts that's good, since it means that a report parameter named 
    # "username" won't get misinterpreted as an attempt to login.
    # 
    } elsif ($$args_href {'allow_login'}) {
        &Jarvis::Error::Debug ("Login attempt on '" . $$args_href{'sid'} . "'.", %$args_href);

        # Get our login parameter values.  We were using $axml->{login}{parameter}('[@]', 'name');
        # but that seemed to cause all sorts of DataDumper and cleanup problems.  This seems to
        # work smoothly.
        my %login_parameters = ();
        if ($axml->{'login'}{'parameter'}) {
            foreach my $parameter ($axml->{'login'}{'parameter'}('@')) {
                &Jarvis::Error::Debug ("Login Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content, %$args_href);
                $login_parameters {$parameter->{'name'}->content} = $parameter->{'value'}->content;
            }
        }
        ($error_string, $username, $group_list) = &Jarvis::Login::Check (\%login_parameters, $args_href);
        $username || ($username = '');
        $group_list || ($group_list = '');

        $logged_in = (($error_string eq "") && ($username ne "")) ? 1 : 0;
        $session->param('logged_in', $logged_in);
        $session->param('username', $username);
        $session->param('group_list', $group_list);

    # Fail because login not allowed.
    } else {
        $error_string = "Not logged and login disallowed for this request";
    }
    $logged_in || &Jarvis::Error::Log ("Login fail: $error_string", %$args_href);

    # Set/extend session expiry.  Flush new/modified session data.
    my $session_expiry = $axml->{'sessiondb'}->{'expiry'}->content || '+1h';
    $session->expire ($session_expiry);
    $session->flush ();

    # Add to our $args_href since e.g. fetch queries might use them.
    $$args_href{'logged_in'} = $logged_in;
    $$args_href{'username'} = $username;
    $$args_href{'error_string'} = $error_string;
    $$args_href{'group_list'} = $group_list;

    return 1;
}

################################################################################
# Checks that a given group list grants access to the currently logged in user
# or the current public (non-logged-in) user.  All this permission check is
# currently performed by group matching.  We don't provide any way to control
# access for individual users within a group.
#
#    ""   -> Allow nobody at all.
#    "**" -> Allow all and sundry.
#    "*"  -> Allow all logged-in users.
#    "group,[group]"  -> Allow those in one (or more) of the named groups.
#
# Params:
#       Permission ("read" or "write")
#       Hash of Args (* indicates mandatory)
#               logged_in, username, group_list
#
# Returns:
#       "" on success.
#       "<Failure description message>" on failure.
################################################################################
#
sub CheckAccess {
    my ($allowed_groups, %args) = @_;

    # Check permissions
    if ($allowed_groups eq "") {
        return "This resource does not allow access to anybody.";

    # Allow access to all even those not logged in.
    } elsif ($allowed_groups eq "**") {
        return "";

    # Allow access to any logged in user.
    } elsif ($allowed_groups eq "*") {
        $args{'logged_in'} || return "Successful login is required in order to access this resource.";

    # Allow access to a specific comma-separated group list.
    } else {
        my $allowed = 0;
        foreach my $allowed_group (split (',', $allowed_groups)) {
            foreach my $member_group (split (',', $args{'group_list'})) {
                if ($allowed_group eq $member_group) {
                    $allowed = 1;
                    last;
                }
            }
            last if $allowed;
        }
        $allowed || return "Logged-in user does not belong to any permitted access group for this resource.";
    }
    return "";
}

1;