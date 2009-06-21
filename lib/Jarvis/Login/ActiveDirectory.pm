###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.  This module checks usernames
#       and passwords via ActiveDirectory (Microsoft's LDAP Implementation).
#
#       Refer to the documentation for the "check" function for how
#       to configure your <application>.xml to use this login module.
#
# Licence:
#       This file is part of the Jarvis WebApp/LDAP gateway utility.
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
use CGI;

use strict;
use warnings;

use Net::LDAP;

use Jarvis::Error;

package Jarvis::Login::ActiveDirectory;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing user/pass.  We validate this by checking a table in the
# currently open database.  The user and pass columns are both within this same
# table.
#
# To use this method, specify the following login parameters.
#
#    <app use_placeholders="yes" format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::ActiveDirectory">
#  	     <parameter name="server" value="<server-address>"/>
#  	     <parameter name="port" value="389"/>
#  	     <parameter name="bind_username" value="<bind-username>"/>
#  	     <parameter name="bind_password" value="<bind-password>"/>
#            <parameter name="base_object" value="OU=PORSENZ,DC=PORSENZ,DC=LOCAL"/>
#        </login>
#        ...
#    </app>
#
#       server:   address of server.  Required.
#       port:     port for server.  Default 389.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi
#
#       $username - The offered username
#       $password - The offered password
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::ActiveDirectory::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # No info?
    $username || return ("No username supplied.");
    $password || return ("No password supplied.");

    # Our user name login parameters are here...
    my $server = $login_parameters{'server'};
    my $port = $login_parameters{'port'} || 389;
    my $bind_username = $login_parameters{'bind_username'} || '';
    my $bind_password = $login_parameters{'bind_password'} || '';
    my $base_object = $login_parameters{'base_object'} || '';

    $server || return ("Missing 'server' configuration for Login module ActiveDirectory.");
    $base_object || return ("Missing 'base_object' configuration for Login module ActiveDirectory.");

    # Do that ActiveDirectory thing.  Connect first.  AD uses default LDAP port 389.
    &Jarvis::Error::debug ($jconfig, "Connecting to ActiveDirectory Server: '$server:$port'.");
    my $ldap = Net::LDAP->new ($server, port => $port) || die "Cannot connect to '$server' on port $port\n";

    # Bind with a password.
    #   Protocol = 3 (Default)
    #   Authentication = Simple (Default)
    #
    &Jarvis::Error::debug ($jconfig, "Binding to ActiveDirectory Server: '$server:$port' as '$bind_username'.");
    my $mesg = $ldap->bind ($bind_username, password => $bind_password);

    $mesg->code && die "Bind to server '$server:$port' failed with " . $mesg->code . " '" . $mesg->error . "'";

    # Now search on our base object.
    #   Scope = Whole Tree (Default)
    #   Deref = Always
    #   Types Only = False (default)
    #
    &Jarvis::Error::debug ($jconfig, "Searching for samaccountname = '$username'.");
    $mesg = $ldap->search (
        base => $base_object,
        deref => 'always',
        attrs => ['memberOf'],
        filter => "(samaccountname=$username)"
    );

    # Check that we got success, and exactly one entry.  We can't handle more than
    # one account with the same login ID.
    #
    $mesg->code && die "Search for '$username' failed with " . $mesg->code . " '" . $mesg->error . "'";
    $mesg->count || return "User '$username' not known to ActiveDirectory.";
    ($mesg->count == 1) || return "User '$username' ambiguous in ActiveDirectory.";

    # Get the entry and see who it's for.
    #
    my $entry = $mesg->entry (0);
    my $dn = $entry->dn ();
    &Jarvis::Error::debug ($jconfig, "User DN '$dn'");

    # Now look at the memberOf attribute of this account.  If they don't belong to
    # any groups, that's strange, but probably not impossible.  We let the application
    # sort that out.
    #
    # Build up our group_list, which consists only of the "CN" part of the groups.  Actually,
    # a comma separator was probably a poor choice of separator in our group_list, since
    # full LDAP group specifications use commas for the CN, OU, DC components.  Oh well.
    #
    my @groups = $entry->get_value ('memberOf');
    my $group_list = '';
    foreach my $group (@groups) {
        &Jarvis::Error::debug ($jconfig, "Checking group '$group'.");
        if ($group =~ m/^CN=([^,]+),/) {
            my $cn_group = $1;
            &Jarvis::Error::debug ($jconfig, "Identified as member of '$cn_group'.");
            $group_list .= ($group_list ? "," : "") . $cn_group;
        } else {
            &Jarvis::Error::log ($jconfig, "User '$username' is memberOf group with unsupported name syntax." );
        }

    }
    $ldap->unbind ();

    # Reconnect and check the password.
    &Jarvis::Error::debug ($jconfig, "Connecting to ActiveDirectory Server: '$server:$port'.");
    $ldap = Net::LDAP->new ($server, port => $port) || die "Cannot connect to '$server' on port $port\n";

    $mesg = $ldap->bind ($dn, password => $password);
    if ($mesg->code == 49) {
        return ("Incorrect password.");
    }
    $mesg->code && die "Bind to server '$server:$port' failed with " . $mesg->code . " '" . $mesg->error . "'";
    $ldap->unbind ();

    return ("", $username, $group_list);
}

1;
