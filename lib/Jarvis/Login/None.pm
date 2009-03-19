###############################################################################
# Description:
#       Functions for dealing with login and user authentication.
#
#       This is a "dummy" login module that always returns user = "guest"
#       and groups = ("guest") with no checking.  It's good for testing.
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
# Always returns "yes logged in" as "admin", in group "admin".
#
# Params:
#       %args - Hash of standard args.  None used by this function.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::Check {
    my (%args) = @_;

    return ("", "admin", "admin");
}

1;
