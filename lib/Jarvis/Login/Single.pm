###############################################################################
# Description:
#       Functions for dealing with login and user authentication.
#
#       This is a static login module which simply allows a single named
#       user to access with the single named password.  It may also be
#       restricted to a single IP address and optionally HTTPS only.
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
use CGI;
use CGI::Cookie;

use strict;
use warnings;

package Jarvis::Login::Single;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Always returns "yes logged in" as "guest", in group "guest".
#
# You can override the returned username and and group_list as follows, e.g.
#
#    <app format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Single">
#            <parameter name="require_https" value="no"/>
#            <parameter name="remote_ip" value="127.0.0.1,192.168.2.2"/>
#            <parameter name="username" value="bob"/>
#            <parameter name="password" value="test"/>
#            <parameter name="group_list" value="default"/>
#        </login>
#        ...
#   </app>
#
# The "group_list" parameter in you config may be a single group, or a comma
# separated list of groups.
#
# Params:
#       $jconfig - Jarvis::Config object (not used)
#
#       $username - The offered username (IGNORED)
#       $password - The offered password (IGNORED)
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.

#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::Single::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    my $require_https = defined ($Jarvis::Config::yes_value {lc ($login_parameters{'require_https'} || "no")});
    my $remote_ip_list = $login_parameters{'remote_ip'} || '';
    my $expected_username = $login_parameters{'username'};
    my $expected_password = $login_parameters{'password'};
    my $group_list = $login_parameters{'group_list'} || $expected_username;


    # Check basic configuration.  We must have EITHER remote_ip OR a password
    # You can have both, that would be evern better.
    if (! $remote_ip_list && ! $expected_password) {
        return ("Login module Single is not properly configured.  Specify remote_ip and/or password.");
    }

    # Also we must have a username.
    if (! $expected_username) {
        return ("Login module Single is not properly configured.  Specify username.");
    }

    # Do we force HTTPS for this request?
    if ($require_https && ! $jconfig->{'cgi'}->https()) {
        return ("Client must access over HTTPS for this login method.");
    }

    # Check the IP address first.
    if ($remote_ip_list) {
        my $actual_ip = $ENV{"HTTP_X_FORWARDED_FOR"} || $ENV{"HTTP_CLIENT_IP"} || $ENV{"REMOTE_ADDR"} || '';
        &Jarvis::Error::debug ($jconfig, "Actual Remote IP: '$actual_ip'.");
        my $matched = 0;
        foreach my $remote_ip (split (',', $remote_ip_list)) {
            &Jarvis::Error::debug ($jconfig, "Check Against Permitted Remote IP: '$remote_ip'.");
            $matched = ($actual_ip eq $remote_ip);
            last if $matched;
        }
        if (! $matched) {
            return ("Access not authorized from actual remote IP address '$actual_ip'.");
        }
    }

    # If we're using password authentication, then check username and password.
    if ($expected_password) {
        $username || return ("Username must be supplied.");
        ($username eq $expected_username) || return ("Specified username is not known to this system.");
        ($password eq $expected_password) || return ("Password is incorrect.");
    }

    return ("", $expected_username, $group_list);
}

1;
