#NOT FOR RUNNING AS CGI
#
# Description:  Functions for dealing with login and user authentication.
#
#               This is a database module that reads a single table
#               that contains a username and password field, and checks that
#               the supplied pair exists in that table.
###############################################################################
#
use CGI;

use strict;
use warnings;

use Jarvis::Error;

package Jarvis::Login::Database;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing user/pass.  We validate this by checking a table in the 
# currently open database.  The user and pass columns are both within this same
# table.
#
# To use this method, specify the following login parameters.  Note that you
# can omit the group name parameters, in which case all users will be placed
# into a single group named "default".
#  
#    <app name="spiderfan" use_placeholders="yes" format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Database">
# 	   <parameter name="user_table">staff</parameter>
#            <parameter name="user_username_column">name</parameter>
#            <parameter name="user_password_column">password</parameter>
#            <parameter name="group_table">staff_group</parameter>
#            <parameter name="group_username_column">name</parameter>
#            <parameter name="group_group_column">group_name</parameter>
#        </login>
#        ...
#   </app>
#
# Params:
#       $login_parameters_href
#       $args_href
#           $$args_href{'cgi'} - CGI object
#           $$args_href{'dbh'} - DBI object
#
# Returns:
#       ($error_string or "", $username or "" [, group1, group2, group3...])
################################################################################
#
sub Jarvis::Login::Check {
    my ($login_parameters_href, $args_href) = @_;

    # Our user name login parameters are here...
    my $user_table = $$login_parameters_href{'user_table'};
    my $user_username_column = $$login_parameters_href{'user_username_column'};
    my $user_password_column = $$login_parameters_href{'user_password_column'};
    my $group_table = $$login_parameters_href{'group_table'};
    my $group_username_column = $$login_parameters_href{'group_username_column'};
    my $group_group_column = $$login_parameters_href{'group_group_column'};

    if (! ($user_table && $user_username_column && $user_password_column)) {
        return ("Missing configuration for Login module Database.");
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

    # Check the username from the user name table.
    my $query = "SELECT $user_password_column FROM $user_table WHERE $user_username_column = ?";
    my $sth = $$args_href{'dbh'}->prepare ($query) 
            || &Jarvis::Error::MyDie ("Couldn't prepare statement '$query': " . $$args_href{'dbh'}->errstr, %$args_href);
        
    $sth->execute ($username) 
            || &Jarvis::Error::MyDie ("Couldn't execute statement '$query': " . $$args_href{'dbh'}->errstr, %$args_href); 
            
    my $result_aref = $sth->fetchall_arrayref({});
    if ((scalar @$result_aref) < 1) {
        return ("User '$username' not known.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    my $result_href = $$result_aref[0];
    my $stored_password = $$result_href{'password'} || '';

    if ($stored_password eq '') {
        return ("No password stored for user '$username'.");
    }
    if ($stored_password ne $password) {
        return ("Incorrect password for user '$username'.");
    }

    # Need our group configuration, otherwise just put them in group 'default'.
    if (! ($group_table && $group_username_column && $group_group_column)) {
        &Jarvis::Error::Debug ("No group configuration.  Place in group 'default'.", %$args_href);
        return ("", $username, 'default');
    }

    # Fetch group configuration.
    $query = "SELECT $group_group_column FROM $group_table WHERE $group_username_column = ?";
    $sth = $$args_href{'dbh'}->prepare ($query)
            || &Jarvis::Error::MyDie ("Couldn't prepare statement '$query': " . $$args_href{'dbh'}->errstr, %$args_href);
        
    $sth->execute ($username) 
            || &Jarvis::Error::MyDie ("Couldn't execute statement '$query': " . $$args_href{'dbh'}->errstr, %$args_href); 
            
    $result_aref = $sth->fetchall_arrayref({});

    my $group_list = join (",", map { $_->{$group_group_column} } @$result_aref);
    &Jarvis::Error::Debug ("Group list = '$group_list'.", %$args_href);

    return ("", $username, $group_list);
}

1;
