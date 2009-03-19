#NOT FOR RUNNING AS CGI
#
# Description:  Functions for dealing with login and user authentication.
#
#               This is a "dummy" module that always returns user = "guest"
#               and groups = ("guest") with no checking.  It's good for 
#               testing.
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
#       ($error_string or "", $username or "", "group1,group2,group3"
################################################################################
#
sub Jarvis::Login::Check {
    my (%args) = @_;

    return ("", "admin", "admin");
}

1;
