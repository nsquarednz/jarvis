###############################################################################
# Description:  Performs a custom <exec> action defined in the <app_name>.xml
#               file for this application.  A good example of this would be
#               an exec action which handed off to a report script like
#               javis.
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

use MIME::Types;

package Jarvis::Exec;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

################################################################################
# Adds some special variables to our name -> value map.  Note that our special
# variables are added AFTER the user-provided variables.  That means that you
# can securely rely upon the values of __username, __grouplist, etc.  If the
# caller attempts to supply them, ours will replace the hacked values.
#
# Note that this is a subset of the special variables available in datasets.
# Note also that in datasets, the group list is contained in brackets with
# quotes.  Here we pass a simple comma-separated-string.
#
#   __username  -> <logged-in-username>
#   __grouplist -> <group1>,<group2>,...
#
# Params:
#       $param_values_href
#       Hash of Args (* indicates mandatory)
#               user_name, group_list
#
# Returns:
#       1
################################################################################
#
sub AddSpecialExecVariables {
    my ($param_values_href, %args) = @_;

    # These are defined if we have logged in.
    $$param_values_href{"__username"} = $args{'user_name'};
    $$param_values_href{"__grouplist"} = $args{'group_list'};

    return 1;
}
################################################################################
# Shows our current connection status.
#
# Params: Hash of Args (* indicates mandatory)
#       exec, *logged_in, *user-name, *error_string, *group_list
#
# Returns:
#       1.
#       die on error.
################################################################################
#
sub Do {
    my (%args) = @_;

    # Get and check our exec parameters.
    my $action = $args{'action'};
    my $access = $args{'exec'}{$action}{'access'};
    my $command = $args{'exec'}{$action}{'command'};
    my $add_headers = $args{'exec'}{$action}{'add_headers'};
    my $filename_parameter = $args{'exec'}{$action}{'filename_parameter'};

    ($add_headers && ! $filename_parameter) && &Jarvis::Error::MyDie ("Config for exec '$action' has 'add_headers' but no 'filename_parameter'", %args);

    # Check security.
    my $allowed_groups = $access;
    my $failure = &Jarvis::Config::CheckAccess ($access, %args);
    ($failure ne '') && &Jarvis::Error::MyDie ("Wanted exec access: $failure", %args);

    # Get our parameters.  Note that our special variables like __username will
    # override sneaky user-supplied values.
    #
    my %param_values = $args{'cgi'}->Vars;
    &AddSpecialExecVariables (\%param_values, %args);

    # OK, get our filename parameter if required.
    my $filename = undef;
    my $mime_type = undef;

    if ($add_headers) {
        $filename = $param_values {$filename_parameter} ||
            &Jarvis::Error::MyDie ("Missing CGI parameter '$filename_parameter' required for returned filename.", %args);

        my $mime_types = MIME::Types->new;
        $mime_type = $mime_types->mimeTypeOf ($filename) || &Jarvis::Error::MyDie ("Cannot determine mime type from supplied filename '$filename'.", %args);;

        delete $param_values{$filename_parameter};
    }

    # Now delete some other magic system parameters.  These were for jarvis, not for the
    # exec.  If you want your application to have a parameter named "action" then
    # you are out of luck.  Rename it.  Same for "app".
    delete $param_values{"action"};
    delete $param_values{"app"};

    # Add parameters to our command.  Die if any of the parameter names look dodgy.
    # This isn't a problem with datasets, since there we only look at parameters that
    # are coded into our SQL string.  But here we will take ALL parameters supplied
    # by the user, so we need to watch out for any funny business.
    foreach my $param (sort (keys %param_values)) {
        if ($param !~ m/[a-zA-Z0-9_\-]+/) {
            &Jarvis::Error::MyDie ("Unsupported characters in exec parameter name '$param'\n");
        }

        # With the values we are more forgiving, but we quote them up hard in single
        # quotes for the shell.
        my $param_value = $param_values{$param};
        &Jarvis::Error::Debug ("Exec Parameter '$param' = '$param_value'", %args);

        $param_value = &EscapeShell ($param_value);
        $command .= " $param='$param_value'";
    }

    # Execute the command
    &Jarvis::Error::Log ("Executing Command: $command", %args);
    my $output =`$command`;

    # Failure?
    my $status = $?;
    if ($status != 0) {
        &Jarvis::Error::MyDie ("Command failed with status $status.\n$output", %args);
    }

    # Are we supposed to add headers?  Does that include a filename header?
    # Note that if we really wanted to, we could squeeze in 
    if ($add_headers) {

        &Jarvis::Error::Debug ("Exec returned mime type '" . $mime_type->type . "'", %args);

        my $cookie = CGI::Cookie->new (-name => $args{'sname'}, -value => $args{'sid'});
        print $Main::cgi->header(-type => $mime_type->type, 'Content-Disposition' => "inline; filename=$filename", -cookie => $cookie);
    }

    # Now print the output.  If the report didn't add headers like it was supposed
    # to, then this will all turn to custard.
    print $output;
}

1;