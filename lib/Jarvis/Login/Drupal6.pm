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
#            <parameter name="dbname" value="jarvis-config-db-name"/>
#            <parameter name="login_type" value="yes"/>
#            <parameter name="admin_only" value="yes"/>
#            <parameter name="admin_role" value="admin"/>
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
# PERMISSIONS:
#
#       You will probably need:
#
#       GRANT SELECT ON sessions TO "www-data";
#       GRANT SELECT ON users_roles TO "www-data";
#       GRANT SELECT ON role TO "www-data";
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
use CGI::Cookie;

use strict;
use warnings;

package Jarvis::Login::Drupal6;

use Data::Dumper;
use Digest::MD5 qw (md5 md5_hex);
use PHP::Serialization qw(serialize unserialize);

use Jarvis::Error;

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

    # Allow Login.
    #  yes = We accept a supplied username/password and perform user/password checking.
    #
    #  no  = We require that the Drupal login procedure be used.  We only create a Jarvis
    #        session when we see a Drupal session has been created.
    #
    my $login_type = lc ($login_parameters{'login_type'}) || "drupal";

    my $admin_only = defined ($Jarvis::Config::yes_value {lc ($login_parameters{'admin_only'} || "no")});
    my $dbname = $login_parameters{'dbname'} || 'default';

    # See if we can find a Drupal session.
    my $logged_in = 0;
    my $uid = undef;

    # Login Type "drupal" means that we MUST have an existing Drupal session.  We
    # never perform a username/password check ourselves.
    #
    if ($login_type eq "drupal") {
        my %cookies = fetch CGI::Cookie;
        &Jarvis::Error::debug ($jconfig, "Checking for any existing Drupal session cookie.");

        foreach my $cookie_name (keys %cookies) {
            next if $cookie_name !~ m/^SESS/;
            my $cookie_value = $cookies{$cookie_name}->value;

            &Jarvis::Error::debug ($jconfig, "Checking existing Drupal sid '$cookie_value'.");
            my $dbh = &Jarvis::DB::handle ($jconfig, $dbname);

            my $result_aref = $dbh->selectall_arrayref("SELECT u.uid, u.name FROM sessions s INNER JOIN users u ON u.uid = s.uid WHERE s.sid = ?", { Slice => {} }, $cookie_value);

            if ((scalar @$result_aref) >= 1) {
                my $result_href = $$result_aref[0];
                $uid = $$result_href{'uid'};

                if (! $uid) {
                    &Jarvis::Error::debug ($jconfig, "Session has expired.  Look for any other cookies.");
                    next;
                }

                &Jarvis::Error::debug ($jconfig, "Found existing Drupal session for uid $uid, name '$username'.");
                if ($admin_only && ($uid != 1)) {
                    &Jarvis::Error::debug ($jconfig, "Ignoring this one, we require an admin session.");
                    $uid = undef;

                } else {
                    $username = $$result_href{'name'} || die "No uid for sid '$cookie_value'!\n";
                    $logged_in = 1;
                    last;
                }

            } else {
                &Jarvis::Error::debug ($jconfig, "No such Drupal session (or unknown uid).");
            }
        }
        if (! $logged_in) {
            return ("Could not locate existing Drupal session.");
        }

    # Login Type "jarvis" means that we will never look at a Drupal session, we will always
    # maintain our own session independent of the Drupal login.
    #
    } elsif ($login_type eq "jarvis") {
        &Jarvis::Error::debug ($jconfig, "Trying the Jarvis login process for Drupal.");

        $username || return ("No username supplied.");
        $password || return ("No password supplied.");

        # Check the username from the user name table.
        my $dbh = &Jarvis::DB::handle ($jconfig);
        my $result_aref = $dbh->selectall_arrayref("SELECT uid, pass FROM users WHERE name = ? AND status = 1", { Slice => {} }, $username);
        if ((scalar @$result_aref) < 1) {
            return ("User '$username' not known/active.");
        }
        if ((scalar @$result_aref) > 1) {
            return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
        }
        my $result_href = $$result_aref[0];
        $uid = $$result_href{'uid'} || die "No uid for user '$username'!\n";
        my $stored_password = $$result_href{'pass'} || '';

        if ($stored_password eq '') {
            return ("Account has no password.");
        }

        # Check the password.  MD5.  NO SALT!
        # Yes, I know this is vulnerable to dictionary, but that's Drupal's decision not mine.
        #
        &Jarvis::Error::debug ($jconfig, "Checking password hash.");
        if (length ($stored_password) != 32) {
            return ("Stored password is invalid length for MD5");
        }
        my $md5_salt_prefix_len = 0;
        my $salt = substr ($stored_password, 0, $md5_salt_prefix_len);
        my $stored_md5 = substr ($stored_password, $md5_salt_prefix_len);

        if (&Digest::MD5::md5_hex ($salt . $password) ne $stored_md5) {
            return ("Incorrect password hash.");
        }
        &Jarvis::Error::debug ($jconfig, "Password hash valid.  Checking admin requirements.");
        if ($admin_only && ($uid != 1)) {
            return ("Must be Drupal initial admin user.");
        }
        $logged_in = 1;

    } else {
        die "Unrecognised Drupal6 login_type '$login_type'\n";
    }

    # By now we MUST have logged in.
    $uid || die;

    # Determine groups list.
    my $group_list = "";

    # Admin users don't have regular roles.  We give them a single, special group.
    if ($uid == 1) {
        $group_list = $login_parameters{"admin_role"} || "admin";

    # Regular users have their roles in the users_roles table.
    } else {
        my $dbh = &Jarvis::DB::handle ($jconfig, $dbname);
        my $result_aref = $dbh->selectall_arrayref("SELECT r.name FROM users_roles ur INNER JOIN role r ON r.rid = ur.rid WHERE ur.uid = ?", { Slice => {} }, $uid);

        my @role_names = map { $_->{name} } @$result_aref;
        $group_list = join (',', @role_names);
    }

    # Add safe params.
    my %safe_params = (
        '__uid' => $uid
    );

    &Jarvis::Error::debug ($jconfig, "Group list = '$group_list'.");
    return ("", $username, $group_list, \%safe_params);
}

1;
