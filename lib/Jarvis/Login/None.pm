###############################################################################
# Description:
#       Functions for dealing with login and user authentication.
#
#       This is a "dummy" login module that always returns user = "admin"
#       and groups = ("admin") with no checking.  It's good for testing.
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

package Jarvis::Login::None;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Always returns "yes logged in" as "guest", in group "guest".
#
# You can override the returned username and and group_list as follows, e.g.
#
#    <app use_placeholders="yes" format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Database">
# 	     <parameter name="username" value="admin"/>
#            <parameter name="group_list" value="admin"/>
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
#       $login_parameters_href - Hash of login parameters parsed from
#               the master application XML file by the master Login class.

#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::None::Check {
    my ($jconfig, $login_parameters_href) = @_;

    my $username = $$login_parameters_href{'username'} || "guest";
    my $group_list = $$login_parameters_href{'group_list'} || "guest";

    return ("", $username, $group_list);
}

1;
