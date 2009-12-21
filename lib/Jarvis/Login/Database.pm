###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.  This module fetches
#       usernames and passwords from a database table, and optionally
#       fetches group ownership from a second database table.
#
#       Refer to the documentation for the "check" function for how
#       to configure your <application>.xml to use this login module.
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
#    <app format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Database">
#  	     <parameter name="user_table" value="staff"/>
#            <parameter name="user_username_column" value="name"/>
#            <parameter name="user_password_column" value="password"/>
#            <parameter name="group_table" value="staff_group"/>
#            <parameter name="group_username_column" value="name"/>
#            <parameter name="group_group_column" value="group_name"/>
#        </login>
#        ...
#    </app>
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi
#               Database config indirectly via Jarvis::DB
#
#       $username - The offered username
#       $password - The offered password
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::Database::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # No info?
    $username || return ("No username supplied.");
    $password || return ("No password supplied.");

    # Our user name login parameters are here...
    my $user_table = $login_parameters{'user_table'};
    my $user_username_column = $login_parameters{'user_username_column'};
    my $user_password_column = $login_parameters{'user_password_column'};
    my $group_table = $login_parameters{'group_table'};
    my $group_username_column = $login_parameters{'group_username_column'};
    my $group_group_column = $login_parameters{'group_group_column'};

    if (! ($user_table && $user_username_column && $user_password_column)) {
        return ("Missing configuration for Login module Database.");
    }

    # Check the username from the user name table.
    my $query = "SELECT $user_password_column FROM $user_table WHERE $user_username_column = ?";

    my $dbh = &Jarvis::DB::handle ($jconfig);
    my $sth = $dbh->prepare ($query)
            || die "Couldn't prepare statement '$query': " . $dbh->errstr;

    $sth->execute ($username)
            || die "Couldn't execute statement '$query': " . $dbh->errstr;

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
        return ("Account has no password.");
    }
    if ($stored_password ne $password) {
        return ("Incorrect password.");
    }

    # Need our group configuration, otherwise just put them in group 'default'.
    if (! ($group_table && $group_username_column && $group_group_column)) {
        &Jarvis::Error::debug ($jconfig, "No group configuration.  Place in group 'default'.");
        return ("", $username, 'default');
    }

    # Fetch group configuration.
    $query = "SELECT $group_group_column FROM $group_table WHERE $group_username_column = ?";
    $sth = $dbh->prepare ($query)
            || die "Couldn't prepare statement '$query': " . $dbh->errstr;

    $sth->execute ($username)
            || die "Couldn't execute statement '$query': " . $dbh->errstr;

    $result_aref = $sth->fetchall_arrayref({});

    my $group_list = join (",", map { $_->{$group_group_column} } @$result_aref);
    &Jarvis::Error::debug ($jconfig, "Group list = '$group_list'.");

    return ("", $username, $group_list);
}

1;
