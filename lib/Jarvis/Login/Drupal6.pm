###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.
#
#       This module is specifically for Drupal, the open source CMS.  This
#       provides a very simple authentication mechanism.
#
#       We do not create or manage an official Drupal session.  We simply
#       hover on the edges of Drupal and try not to make too much of a mess.
#
# CONFIGURATION:
#
#       To use this method, specify the following login parameters.  e.g.
#
#    <app format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Drupal">
#            <parameter name="admin_only" value="yes"/>
#        </login>
#        ...
#    </app>
#
# GROUP LIST:
#
#       The group list is either
#          "admin,user" (if the user's uid = 1), or
#          "user" (all other users)
#
# SPECIAL PARAMETERS:
#
#       This module also returns some additional secure parameters to be
#       stored in the session file and made available to all requests as
#       safe params.
#
#           "__uid"  - Value of "uid" from the Drupal "users" table.
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
#       This software is Copyright 2010 by Jonathan Couper-Smartt.
###############################################################################
#
use Socket;
use CGI;

use strict;
use warnings;

use Digest::MD5 qw (md5 md5_hex);

use Jarvis::Error;

package Jarvis::Login::Drupal6;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing user/pass.  We validate this by checking a table in the
# currently open database.  The user and pass columns are both within this same
# table.
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
sub Jarvis::Login::Drupal6::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # Config.
    my $admin_only = defined ($Jarvis::Config::yes_value {lc ($login_parameters{'admin_only'} || "no")});

    # No info?
    $username || return ("No username supplied.");
    $password || return ("No password supplied.");

    my $dbh = &Jarvis::DB::handle ($jconfig);

    # Check the username from the user name table.
    my $query = "SELECT uid, pass FROM users WHERE name = ? AND status = 1";

    my $sth = $dbh->prepare ($query) || die "Couldn't prepare statement '$query': " . $dbh->errstr;
    $sth->execute ($username) || die "Couldn't execute statement '$query': " . $dbh->errstr;

    my $result_aref = $sth->fetchall_arrayref({});
    $sth->finish ();

    if ((scalar @$result_aref) < 1) {
        return ("User '$username' not known/active.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    my $result_href = $$result_aref[0];
    my $uid = $$result_href{'uid'} || '';
    my $stored_password = $$result_href{'pass'} || '';

    if ($stored_password eq '') {
        return ("Account has no password.");
    }
    $uid || die "No uid for user '$username'!";


    # Check the password.  MD5.  NO SALT!
    # Yes, I know this is vulnerable to dictionary, but that's Drupal's decision not mine.
    #
    if (length ($stored_password) != 32) {
        return ("Stored password is invalid length for MD5");
    }
    my $md5_salt_prefix_len = 0;
    my $salt = substr ($stored_password, 0, $md5_salt_prefix_len);
    my $stored_md5 = substr ($stored_password, $md5_salt_prefix_len);

    if (&Digest::MD5::md5_hex ($salt . $password) ne $stored_md5) {
        return ("Incorrect password hash.");
    }

    # Check admin_only flag.
    if ($admin_only && ($uid != 1)) {
        return ("Must be Drupal initial admin user.");
    }

    # Set groups list.
    my $group_list = ($uid == 1) ? "admin,user" : "user";

    # Add safe params.
    my %safe_params = (
        '__uid' => $uid
    );

    &Jarvis::Error::debug ($jconfig, "Group list = '$group_list'.");
    return ("", $username, $group_list, \%safe_params);
}

1;
