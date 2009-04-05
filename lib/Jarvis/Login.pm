###############################################################################
# Description:  This is a wrapper which loads and hands off to a specific
#               login module depending on the login protocol being used.
#
#               We will check for session cookies, and will only require login
#               if we can't locate an active valid session.
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

package Jarvis::Login;

use Jarvis::Error;

################################################################################
# Checks to see if we are logged in.  If permitted, we will create a new
# session if possible.
#
# If we do a login, this will extend/modify some parameters in our Jasper::Config
# object to show our current login status.
#
# Params:
#       $jconfig   - Jasper::Config object
#           READS
#               Database config indirectly via Login Modules and Jarvis::DB
#
#           WRITES
#               logged_in           Did a user log in?
#               username            Which user logged in?
#               error_string        What error if not logged in?
#               group_list          Comma-separated group list.
#               sname               Name of the session cookie.  Typically "CGISESSID".
#               sid                 Session ID.  A big long number.
#
#       $allow_new_login - Are we allowed to actually perform the login process?
#           If not, then we are restricted to only validating existing logins.
################################################################################
#
sub check {
    my ($jconfig, $allow_new_login) = @_;

    ###############################################################################
    # Login Process.  Happens after DB, 'cos login info can be in DB.
    ###############################################################################
    #
    my $axml = $jconfig->{'xml'}->{jarvis}{app};
    (defined $axml) || die "Cannot find <jarvis><app> in '" . $jconfig->{'app_name'} . ".xml'!\n";

    # Where are our sessions stored?
    my $sid_store = $axml->{'sessiondb'}->{'store'}->content || "driver:file;serializer:default;id:md5";
    &Jarvis::Error::debug ($jconfig, "SID Store '$sid_store'.");

    my %sid_params = ();
    if ($axml->{'sessiondb'}->{'parameter'}) {
        foreach my $sid_param (@{ $axml->{'sessiondb'}->{'parameter'} }) {
            $sid_params {$sid_param->{'name'}->content} = $sid_param->{'value'}->content;
        }
    }

    # Get an existing/new session.
    my $session = new CGI::Session ($sid_store, $jconfig->{'cgi'}, \%sid_params);
    $jconfig->{'sname'} = $session->name();
    $jconfig->{'sid'} = $session->id();

    # By default these values are all empty.  Note that we never allow username
    # and group_list to be undef, too many things depend on it having some value,
    # even if that is just ''.
    # 
    my ($error_string, $username, $group_list, $logged_in) = ('', '', '', 0);
    my $already_logged_in = 0;

    # Existing, successful session?  Fine, we trust this.
    if ($session->param('logged_in') && $session->param('username')) {
        &Jarvis::Error::debug ($jconfig, "Already logged in for session '" . $jconfig->{'sid'} . "'.");
        $logged_in = $session->param('logged_in') || 0;
        $username = $session->param('username') || '';
        $group_list = $session->param('group_list') || '';
        $already_logged_in = 1;

    # No successful session?  Login.  Note that we store failed sessions too.
    # 
    # Note that not all actions allow you to provide a username and password for
    # login purposes.  "status" does, and so does "fetch".  But the others don't.
    # For exec scripts that's good, since it means that a report parameter named 
    # "username" won't get misinterpreted as an attempt to login.
    # 
    } elsif ($allow_new_login) {

        # Get our login parameter values.  We were using $axml->{login}{parameter}('[@]', 'name');
        # but that seemed to cause all sorts of DataDumper and cleanup problems.  This seems to
        # work smoothly.
        my %login_parameters = ();
        if ($axml->{'login'}{'parameter'}) {
            foreach my $parameter ($axml->{'login'}{'parameter'}('@')) {
                &Jarvis::Error::debug ($jconfig, "Login Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
                $login_parameters {$parameter->{'name'}->content} = $parameter->{'value'}->content;
            }
        }

        my $login_module = $axml->{login}{module} || die "Application '" . $jconfig->{'app_name'} . "' has no defined login module.\n";

        &Jarvis::Error::debug ($jconfig, "Loading login module '" . $login_module . "'.");
        eval "require $login_module";
        if ($@) {
            &Jarvis::Error::my_die ($jconfig, "Cannot load login module '$login_module': " . $@);
        }
        my $login_method = $login_module . "::check";
        {
            no strict 'refs';
            ($error_string, $username, $group_list) = &$login_method ($jconfig, %login_parameters);
        }

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

    # Log the attempt ONLY IF they supplied a username and we weren't already logged in.
    if ($username && ! $already_logged_in) {
        if ($logged_in) {
            &Jarvis::Error::log ($jconfig, "Login succeeded for '$username' in '$group_list'");
        } else {
            &Jarvis::Error::log ($jconfig, "Login fail on '" . $jconfig->{'sid'} . "': $error_string");
        }
    }

    # Set/extend session expiry on successful sessions.  Flush new/modified session data.
    if ($logged_in) {
        my $session_expiry = $axml->{'sessiondb'}->{'expiry'}->content || '+1h';
        $session->expire ($session_expiry);
        $session->flush ();
    }

    # Add to our $args_href since e.g. fetch queries might use them.
    $jconfig->{'logged_in'} = $logged_in;
    $jconfig->{'username'} = $username;
    $jconfig->{'error_string'} = $error_string;
    $jconfig->{'group_list'} = $group_list;

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
#       jconfig   - Jasper::Config object
#           READ
#               logged_in
#               username
#               group_list
#
#       $allowed_groups - List of permitted groups or "*" or "**"
#
# Returns:
#       "" on success.
#       "<Failure description message>" on failure.
################################################################################
#
sub check_access {
    my ($jconfig, $allowed_groups) = @_;

    # Check permissions
    if ($allowed_groups eq "") {
        return "This resource does not allow access to anybody.";

    # Allow access to all even those not logged in.
    } elsif ($allowed_groups eq "**") {
        return "";

    # Allow access to any logged in user.
    } elsif ($allowed_groups eq "*") {
        $jconfig->{'logged_in'} || return "Successful login is required in order to access this resource.";

    # Allow access to a specific comma-separated group list.
    } else {
        my $allowed = 0;
        foreach my $allowed_group (split (',', $allowed_groups)) {
            foreach my $member_group (split (',', $jconfig->{'group_list'})) {
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