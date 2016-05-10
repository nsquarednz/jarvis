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
# for the specified user/pass.  We send these off to an executable file which
# tells us a success or fail. It also tells us the users groups and may tell
# additional information to be put into the additional_safe hash.
#
# To use this method, specify the following login parameters.
#
# <app format="json">
#     ...
#     <login module="Jarvis::Login::Executable">
#         <parameter name="executable" value="path to executable"/>
#         <parameter name="allowed_groups" value="comma separated list of allowed user groups"/>
#     </login>
#     ...
# </app>
#
#    Parameters:
#    executable     - Absolute path to executable file for Authentication. <Required>
#    working_dir    - The working directory to execute in.
#                     Default: Directory the executable is in.
#    allowed_groups - Only allow login for users belonging to one of these groups. <Optional> 
#                     Defaults: All Groups '*'.
#
#    Output of executable: Is expected to be json like so.
#    Examples:
#             // Success
#             {
#               "success": 1,
#               "groups": [roles/usergroups],
#               "additional": { ... },
#               "cookies": { ... }
#             }
#
#             // Fail
#             {
#               "success": 0,
#               "message": "Reason why it failed."
#             }
#
#    -- Executable output breakdown --
#    Key         | Description
#    ----------  | ----------------------------------------------------------------------------
#    success     | If successful then 1 otherwise 0 or undefined for fail. <Optional>
#    message     | In the case of an unsuccessful login the reason can be specified. <Optional>
#    groups      | An array of strings naming the user groups or roles applicable to the login.
#                  Or a comma separated list of names. <Optional>
#    additional  | An object of key=values to assign to the session. <Optional>
#                  Key names for safe parameters must start with __ and will be put into $jconfig->{additional_safe}.
#    cookies     | An object of key=values to be turned into cookies on success login. <Optional>
#                  It is up to the developer to ensure the key names are suitable for cookie key names.
#                  Any cookies defined in this hash will be sent to the client in a cookie string.
#
# Params:
#       $jconfig  - Jarvis::Config object
#       $username - The offered username.
#       $password - The offered password.
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...", %additional_safe or undef, %cookies or undef)
####################################################################################################
#
sub Jarvis::Login::Executable::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # Our user name login parameters are here...
    my $executable = $login_parameters{'executable'};
    my $allowed_groups = $login_parameters{'allowed_groups'} || '*';
    my $working_dir = $login_parameters{'working_dir'} || '';

    # Check if no password is require.
    if ($login_parameters{'no_password'}) {
        $login_parameters{'extra'} = 'no_password';
        $password = '';
    } else {
      $password || return "No password supplied.";
    }

    # No info?
    $username || return "No username supplied.";

    # Sanity check on config.
    $executable || return "Missing 'executable' configuration for Login module Executable.";

    if (! (-r $executable && -x _)) {
        die "Unable to find the executable file configured for Login module Executable '$executable'.";
    }

    # Set the working directory to the executables dirname if the working_dir was not specified as a login parameter.
    if ($working_dir eq '') {
        $working_dir = dirname($executable);
    }

    my $extra = '';
    if ($login_parameters{'no_password'}) {
        $extra = 'no_password';
    }

    # Ensure parameters are safe for shell.
    my %safe_params = ("username" => $username, "password" => $password, "extra" => $extra);

    # Note that we will take username and password parameters supplied
    # by the user, so we need to watch out for any funny business.
    foreach my $param (keys %safe_params) {
        # Escape & Quote values for the shell to make them safe.
        my $param_value = shell_quote $safe_params{$param};
        $safe_params{$param} = $param_value;
    }

    # Switch working directory.
    my $old_working_dir = getcwd();
    chdir $working_dir or die "Can't change directory to '$working_dir'.";

    # Execute the executable in an eval to catch any exception/die thrown.
    my $output;

    eval {
        # Temporarily remove die handlers for local block.
        local $SIG{'__DIE__'};
        # Execute the executable passing the username and password getting back the output.
        $output = `$executable $safe_params{username} $safe_params{password} $safe_params{extra}` || return "Login Failed. Execution Error.";
    }; return $@ if $@;

    # Switch working directory back.
    chdir $old_working_dir or die "Can't change directory to '$old_working_dir'.";

    # If no output defined then there may be an internal error executing the file as it did not output the info we want.
    if (! defined $output) {
        return "Login Failed: Internal Error.";
    }

    # This variable will hold the parsed result from the executable output.
    my $result;

    # Do the parsing of the JSON.
    eval {
        local $SIG{'__DIE__'};
        $result = parse_json($output);
    } or die "Unable to parse JSON response from executable. $@";

    # If no result was found.
    if (! defined $result) {
        return "Login Failed: Result not defined.";
    }

    # Check that we got success.
    if (!defined $result->{success} || $result->{success} != 1) {
        my $message = $result->{message} || "";
        &Jarvis::Error::debug ($jconfig, "Failed login '$username' $message.");
        return "Login Failed. $message";
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
    my $group_list = join(',', @{$groups});

    # We got the group list, check if user is allowed.
    if ($allowed_groups) {
        my $allowed_groups_regexp = list_regexp($allowed_groups);
        unless ( scalar(grep { $_ =~ /$allowed_groups_regexp/ } @$groups) ) {
            &Jarvis::Error::debug ($jconfig, "No allowed group for user '$username'.");
            return "Login Denied.";
        }
    }

    # Get any additional safe parameters.
    my $additional_safe = $result->{additional} || {};

    # Get any cookies.
    my $cookies = $result->{cookies} || {};

    &Jarvis::Error::debug ($jconfig, "Password check succeeded for user '$username'.");
    return ("", $username, $group_list, $additional_safe, $cookies);
}

1;
