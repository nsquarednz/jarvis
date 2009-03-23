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
# You can override the returned user_name and and group_list as follows, e.g.
#
#    <app name="myapp" use_placeholders="yes" format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Database">
# 	     <parameter name="user_name">admin</parameter>
#            <parameter name="group_list">admin</parameter>
#        </login>
#        ...
#   </app>
#
# The "group_list" parameter in you config may be a single group, or a comma
# separated list of groups.
#
# Params:
#       $login_parameters_href (configuration for this module)
#       $args_href
#           $$args_href{'cgi'} - CGI object (Not used)
#           $$args_href{'dbh'} - DBI object (Not used)
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::Check {
    my ($login_parameters_href, $args_href) = @_;

    my $user_name = $$login_parameters_href{'user_name'} || "guest";
    my $group_list = $$login_parameters_href{'group_list'} || "guest";

    return ("", $user_name, $group_list);
}

1;
