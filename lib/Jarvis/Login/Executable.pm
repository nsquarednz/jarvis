####################################################################################################
# Description:
#       Jarvis supports pluggable Login modules.
#       This module enables using an external executable or bash command
#       for authenticating a username and password.
#
#       Refer to the documentation for the "check" function for how
#       to configure your <application>.xml to use this login module.
#
# Licence:
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
#       This software is Copyright 2016 by NSquared Software.
####################################################################################################
#
use CGI;

use strict;
use warnings;

package Jarvis::Login::Executable;

use Cwd;
use File::Basename 'dirname';
use Jarvis::Error;
use String::ShellQuote;
use JSON::Parse 'parse_json';

####################################################################################################
# Public Functions
####################################################################################################

####################################################################################################
# Utility Functions
####################################################################################################

# converts a list of strings with * wildcard into a single perl regular expression string
sub list_regexp {
    my @list = @_;
    my $regexp = '';
    foreach my $match (@list) {
        # escape all potential meta-characters
        $match =~ s/([^\w\s\*])/\\$1/g;
        # comma to pipe
        $match =~ s/\\,/\|/g;
        # any whitespace sequence will match any other
        $match =~ s/\s+/\\s+/g;
        # translate * wildcard
        $match =~ s/\*/.*/g;
        # append to regexp
        $regexp .= (length($regexp) > 0 ? "|$match" : $match);
    }
    return $regexp;
}

####################################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing user/pass.  We validate this by checking a table in the
# currently open database.  The user and pass columns are both within this same
# table.
#
# To use this method, specify the following login parameters.
#
# <app format="json" debug="no">
#     ...
#     <login module="Jarvis::Login::Executable">
#     <parameter name="executable" value="/opt/amorini/webapps/amorini/application/cli_login.php"/>
#     <parameter name="allowed_groups" value="superadmin,amorini,retail-head-office,chpl-merchant,qualified-consultant"/>
#     </login>
#     ...
# </app>
#
#    Parameters:
#    executable     - Absolute path to executable file for Authentication. <Required>
#                   : You can specify a shell command by prefixing with a #. Eg: '#cat /tmp/response.json'.
#    allowed_groups - Only allow login for users belonging to one of these groups. <Optional>
#    result_type    - How to parse the result from the executable. Default: 'json'.
#
#
#    Output of executable: Is expected to return in the configured format defaulting to json.
#    Examples:
#             // Success
#             {
#               "success": 1,
#               "groups": [roles/usergroups]
#               "additional": { ... }
#             }
#
#             // Fail
#             {
#               "success": 0,
#               "message": "Reason why it failed."
#             }
#
#    Key         | Description
#    ----------  | ----------------------------------------------------------------------------
#    success     | If successful then 1 otherwise 0 or undefined for fail. <Optional>
#    message     | In the case of an unsuccessful login the reason can be specified. <Optional>
#    groups      | An array of strings naming the user groups or roles applicable to the login.
#                : Or a comma separated list of names. <Optional>
#    additional  | An object of key=values to assign to the session. <Optional>
#                : Key names for safe parameters must start with __ and will be put into $jconfig->{additional_safe}.
#    working_dir | The working directory to execute in. Default: Directory the executable is in or /tmp for # command.
# 
#
# Params:
#       $jconfig  - Jarvis::Config object
#       $username - The offered username.
#       $password - The offered password.
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...", %additional_safe or undef, %additional_cookies or undef)
####################################################################################################
#
sub Jarvis::Login::Executable::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # Our user name login parameters are here...
    my $executable = $login_parameters{'executable'};
    my $allowed_groups = $login_parameters{'allowed_groups'} || '';
    my $result_type = $login_parameters{'result_type'} || 'json';
    my $working_dir = $login_parameters{'working_dir'} || '';

    # No info?
    $username || return ("No username supplied.");
    $password || return ("No password supplied.");

    return ("Invalid username.") if $username !~ m/\w+/ || $username =~ m/^[\|]/;
    return ("Invalid password.") if $password !~ m/\w+/ || $password =~ m/^[\|]/;

    # Sanity check on config.
    $executable || return ("Missing 'executable' configuration for Login module Executable.");

    # Decide if executable is a shell command or an executable.
    my $is_cmd = substr($executable,0, 1) eq '#';
    if ($is_cmd) {
        $executable = substr($executable, 1);
        if ($working_dir eq '') {
            $working_dir = '/tmp';
        }
    } else {
        if ($working_dir eq '') {
            $working_dir = dirname($executable);
        }
    }

    if (! $is_cmd) {
        if (! (-r $executable && -x _)) {
            return ("Unable to find the executable file configured for Login module Executable.");
        }
    }

    # Ensure parameters are safe for shell.
    my %safe_params = ("username" => $username, "password" => $password);

    # Note that we will take username and password parameters supplied
    # by the user, so we need to watch out for any funny business.
    foreach my $param ((keys %safe_params)) {
        # Quote values for the shell.
        my $param_value = shell_quote $safe_params{$param};
        $safe_params{$param} = $param_value;
    }

    # Switch working directory.
    my $old_working_dir = getcwd();
    chdir $working_dir or warn "Can't change directory to '$working_dir'.";

    # Execute the executable in an eval to catch any exception/die thrown.
    my $output;
    eval {
        # Execute the executable passing the username and password getting back the output.
        $output = `$executable $safe_params{username} $safe_params{password}` || return ("Login Failed. Execution Error.");
    }; warn $@ if $@;

    # Switch working directory back.
    chdir $old_working_dir or warn "Can't change directory to '$old_working_dir'.";

    # If no output defined then there must be an internal error executing the file.
    if (! defined $output) {
        return ("Login Failed: Internal Error.");
    }

    # This variable will hold the parsed result from the executable output.
    my $result;

    # Process the results by type.
    if ($result_type eq 'json') {
        $result = parse_json($output);
    } else {
        return ("Login Failed: Unhanded result type configured.");
    }

    # If no result was found.
    if (! defined $result) {
        return ("Login Failed: Result not defined.");
    }

    # Check that we got success.
    if (defined $result->{success} && $result->{success} != 1 || ! defined $result->{success}) {
        my $message = $result->{message} || "";
        &Jarvis::Error::debug ($jconfig, "Failed login '$username' $message.");
        return ("Login Failed. $message");
    }

    # Get the groups from the result.
    my $groups;
    if (defined $result->{groups}) {
        if(ref($result->{groups}) eq 'ARRAY'){
            $groups = $result->{groups};
        } else {
            # Handle the case where a comma separated list of groups can be passed back.
            @{ $groups } = split(',',$result->{groups});
        }
    } else {
        $groups = [];
    }

    # Get the group list string.
    my $group_list = '';
    foreach my $group (@$groups) {
        $group_list .= ($group_list ? ',' : '') . $group;
    }

    # We got the group list, check if user is allowed.
    if ($allowed_groups) {
        my $allowed_groups_regexp = list_regexp($allowed_groups);
        unless ( scalar(grep { $_ =~ /$allowed_groups_regexp/ } split(',', $group_list)) ) {
            &Jarvis::Error::debug ($jconfig, "No allowed group for user '$username'.");
            return ("Login Denied.");
        }
    }

    # Get any additional safe parameters.
    my $additional_safe = $result->{additional} || {};

    # Get any additional cookies.
    my $additional_cookies = undef;
    if (defined $result->{cookies}) {
        if (ref($result->{cookies}) eq 'HASH') {
            $additional_cookies = $result->{cookies};
        } else {
            &Jarvis::Error::debug ($jconfig, "Expecting execution result cookies to be a hash.");
        }
    }

    &Jarvis::Error::debug ($jconfig, "Password check succeeded for user '$username'.");
    return ("", $username, $group_list, $additional_safe, $additional_cookies);
}

1;
