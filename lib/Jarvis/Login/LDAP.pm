###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.  This module checks usernames
#       and passwords via LDAP.
#
#       Refer to the documentation for the "Check" function for how
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

package Jarvis::Login::LDAP;

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
#        <login module="Jarvis::Login::LDAP">
#            <parameter name="flavor" value="activedirectory/>      
#  	     <parameter name="server" value="server-address"/>
#  	     <parameter name="port" value="389"/>
#            <parameter name="suffix" value="OU=BorisOffices,OU=PORSE HQ USERS,OU=PORSENZ,DC=PORSENZ,DC=LOCAL"/>
#        </login>
#        ...
#    </app>
#
#       flavor:   "ldap" (default) or "activedirectory"
#       server:   address of server.  Required.
#       port:     port for server.  Default 389.
#       suffix:   The office unit & domain component suffix to append to CN=<user>
#
# Params:
#       $login_parameters_href (configuration for this module)
#       $args_href
#           $$args_href{'cgi'} - CGI object
#           $$args_href{'dbh'} - DBI object
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::Check {
    my ($login_parameters_href, $args_href) = @_;

    # Our user name login parameters are here...
    my $flavor = lc ($$login_parameters_href{'flavor'} || 'ldap');
    my $server = $$login_parameters_href{'server'};
    my $port = $$login_parameters_href{'port'} || 389;
    my $suffix = $$login_parameters_href{'suffix'};

    if (! ($server && $suffix)) {
        return ("Missing configuration for Login module LDAP.");
    }
    if (($flavor ne 'ldap') && ($flavor ne 'activedirectory')) {
        return ("Unsupported LDAP flavor '$flavor' in configuration.");
    }

    # Now see what we got passed.
    my $username = $$args_href{'cgi'}->param('username');
    my $password = $$args_href{'cgi'}->param('password');

    # No info?
    if (! ((defined $username) && ($username ne ""))) {
        return ("No username supplied.");

    } elsif (! ((defined $password) && ($password ne ""))) {
        return ("No password supplied.");
    }

    # Do that LDAP thing.  Connect first.
    &Jarvis::Error::Debug ("Connecting to LDAP Server: '$server:$port'.", %$args_href);
    my $ldap = Net::LDAP->new ($server, port => $port) || die "Cannot connect to '$server' on port $port\n";

    # Bind with a password.
    my $name = "CN=$username,$suffix";
    &Jarvis::Error::Debug ("Binding to LDAP Server: '$server:$port' as '$name'.", %$args_href);
    my $mesg = $ldap->bind ($name, password => $password);

    $mesg->code && die "Bind to server '$server' failed with " . $mesg->code . " '" . $mesg->error . "'\n";

    return ("Still working...");
    # return ("", $username, "blah");
}

1;
