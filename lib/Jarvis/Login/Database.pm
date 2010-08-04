###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.  This module fetches
#       usernames and passwords from a database table, and optionally
#       fetches group ownership from a second database table.
#
#       Passwords can be encrypted.
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
#            <parameter name="user_table" value="staff"/>
#            <parameter name="user_id_column" value="id"/>
#            <parameter name="user_username_column" value="name"/>
#            <parameter name="user_password_column" value="password"/>
#            <parameter name="group_table" value="staff_group"/>
#            <parameter name="group_username_column" value="name"/>
#            <parameter name="group_group_column" value="group_name"/>
#
#            ...
#            <parameter name="encryption" value="none|md5|eksblowfish"/>
#            <parameter name="salt_prefix_len" value="2"/> <!-- Note, for eksblowfish, this must be 16, so you don't need to specify this -->
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
# Note that for eksblowfish, the password is stored in the database in the
# form:
#   salt+encrypted_password
#
# where the '+' is a distinct character. salt must be 16 characters.
#
# To encrypt a eksblowfish password, use the following perl code:
#
#    use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash);
#    my $salt = "abcdefghijklmnop";
#    my $hash = $salt . '+' . bcrypt_hash({ key_nul => 1, cost => 8, salt => $salt }, "mypassword");
#
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::Database::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # Additional safe parameters?
    my %additional_safe = ();

    # No info?
    $username || return ("No username supplied.");
    $password || return ("No password supplied.");

    # Our user name login parameters are here...
    my $user_table = $login_parameters{'user_table'};
    my $user_id_column = $login_parameters{'user_id_column'};
    my $user_username_column = $login_parameters{'user_username_column'};
    my $user_password_column = $login_parameters{'user_password_column'};
    my $group_table = $login_parameters{'group_table'};
    my $group_username_column = $login_parameters{'group_username_column'};
    my $group_group_column = $login_parameters{'group_group_column'};

    # Does the database store plain text, a MD5 hash (in HEX format, we don't support binary), 
    # or a HEX formatted version of an Eksblowfish encrypted password?
    my $encryption = lc ($login_parameters{'encryption'} || "none");

    # Does the database encryption, if there is some include "N" digits of ASCII salt, 
    # which we also prefix to the password before hashing it?
    my $salt_prefix_len = $login_parameters{'salt_prefix_len'} || 0;

    # Sanity check our args.
    if (! ($user_table && $user_username_column && $user_password_column)) {
        return ("Missing configuration for Login module Database.");
    }

    my $dbh = &Jarvis::DB::handle ($jconfig);

    # Check the username from the user name table.
    my $user_columns = $user_password_column . ($user_id_column ? ", $user_id_column": "");
    my $result_aref = $dbh->selectall_arrayref("SELECT $user_columns FROM $user_table WHERE $user_username_column = ?", { Slice => {} }, $username);
    if ((scalar @$result_aref) < 1) {
        return ("User '$username' not known.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    my $result_href = $$result_aref[0];
    my $stored_password = $$result_href{$user_password_column} || '';

    if ($stored_password eq '') {
        return ("Account has no password.");
    }

    # Check the password.
    if ($encryption eq "md5") {
        if (length ($stored_password) != ($salt_prefix_len + 32)) {
            return ("Stored password is invalid length for MD5 + salt");
        }
        my $salt = substr ($stored_password, 0, $salt_prefix_len);
        my $stored_md5 = substr ($stored_password, $salt_prefix_len);

        eval "use Digest::MD5 qw (md5 md5_hex);";
        if (&Digest::MD5::md5_hex ($salt . $password) ne $stored_md5) {
            return ("Incorrect password.");
        }

    } elsif ($encryption eq "eksblowfish") {
        $salt_prefix_len = 16; # eksblowfish requires a salt of 16. 
        if (length ($stored_password) <= $salt_prefix_len) {
            return ("Stored password is invalid length for Eksblowfish + salt");
        }
        my $salt = substr ($stored_password, 0, $salt_prefix_len);
        my $p = substr ($stored_password, $salt_prefix_len + 1); 

        eval "use Crypt::Eksblowfish::Bcrypt qw(bcrypt_hash);";
        my $hash = &Crypt::Eksblowfish::Bcrypt::bcrypt_hash({
                key_nul => 1,
                cost => 8,
                salt => $salt
        }, $password);
        my $checkVal = unpack("H*", $hash);
        &Jarvis::Error::debug ($jconfig, $checkVal . " vs " . $p);
        if ($checkVal ne $p) {
            return ("Incorrect password.");
        }
    } else {
        if ($stored_password ne $password) {
            return ("Incorrect password.");
        }
    }

    # Add __user_id parameter?
    if ($user_id_column) {
        $additional_safe{'__user_id'} = $$result_href{$user_id_column};
    }

    # Need our group configuration, otherwise just put them in group 'default'.
    if (! ($group_table && $group_username_column && $group_group_column)) {
        &Jarvis::Error::debug ($jconfig, "No group configuration.  Place in group 'default'.");
        return ("", $username, 'default');
    }

    # Fetch group configuration.
    $result_aref = $dbh->selectall_arrayref("SELECT $group_group_column FROM $group_table WHERE $group_username_column = ?", { Slice => {} }, $username);
    my $group_list = join (",", map { $_->{$group_group_column} } @$result_aref);
    &Jarvis::Error::debug ($jconfig, "Group list = '$group_list'.");

    return ("", $username, $group_list, \%additional_safe);
}

1;
