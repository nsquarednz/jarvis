###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.
#
#       This module is specifically for Adempiere, the open source ERM
#       system.  It logs the user in according to the ad_user, ad_user_roles,
#       ad_role and ad_window_access tables.
#
#       Note: This module currently supports only users from a single, statically
#       configured organisation and client.
#
# CONFIGURATION:
#
#       To use this method, specify the following login parameters.  e.g.
#
#    <app format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::Adempiere">
#            <parameter name="client_name" value="MyCompany"/>
#            <parameter name="org_name" value="MyCompany"/>
#        </login>
#        ...
#    </app>
#
# GROUP LIST:
#
#       The group list is a LONG comma-separated
#       string where each of the many elements is either.
#
#       role-<role_name>        For each active user role.
#       read-<window_name>      For each active window access (read access)
#       write-<window_name>     For each active window access (write access)
#
#       All spaces and special characters are stripped from the role name
#       and window names.
#
#       So for window "My Window", your corresponding dataset is likely to
#       have access settings
#
#               read="read-MyWindow,write-MyWindow" write="write-MyWindow"
#
# SPECIAL PARAMETERS:
#
#       This module also returns some additional secure parameters to be
#       stored in the session file and made available to all requests as
#       safe params.
#
#           "__ad_client_id"  - Value of ad_client_id matching our "client_name"
#           "__ad_org_id"  - Value of ad_client_id matching our "org_name"
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
use Socket;
use CGI;

use strict;
use warnings;

use Jarvis::Error;

package Jarvis::Login::Adempiere;

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
sub Jarvis::Login::Adempiere::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # No info?
    $username || return ("No username supplied.");
    $password || return ("No password supplied.");

    # Client & Org Name
    my $client_name = $login_parameters{'client_name'};
    my $org_name = $login_parameters{'org_name'};

    my $dbh = &Jarvis::DB::handle ($jconfig);

    # Get the Client ID
    my $result_aref = $dbh->selectall_arrayref("SELECT ad_client_id FROM ad_client WHERE name = ? AND isactive = 'Y'", { Slice => {} }, $client_name);
    if ((scalar @$result_aref) < 1) {
        return ("Client '$client_name' not known/active.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("Client '$client_name' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    my $result_href = $$result_aref[0];
    my $ad_client_id = $$result_href{'ad_client_id'} || die "Client '$client_name' has no ad_client_id.";
    &Jarvis::Error::debug ($jconfig, "Client ID = '$ad_client_id'.");


    # Get the Org ID
    $result_aref = $dbh->selectall_arrayref("SELECT ad_org_id FROM ad_org WHERE name = ? AND isactive = 'Y'", { Slice => {} }, $org_name);
    if ((scalar @$result_aref) < 1) {
        return ("Org '$org_name' not known/active.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("Org '$org_name' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    $result_href = $$result_aref[0];
    my $ad_org_id = $$result_href{'ad_org_id'} || die "Org '$org_name' has no ad_org_id.";
    &Jarvis::Error::debug ($jconfig, "Org ID = '$ad_org_id'.");


    # Check the username from the user name table.
    $result_aref = $dbh->selectall_arrayref("SELECT ad_user_id, password FROM ad_user WHERE name = ? AND isactive = 'Y' AND (ad_client_id = ? OR ad_client_id = 0) AND (ad_org_id = ? OR ad_org_id = 0)", { Slice => {} }, $username, $ad_client_id, $ad_org_id);
    if ((scalar @$result_aref) < 1) {
        return ("User '$username' not known/active.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    $result_href = $$result_aref[0];
    my $ad_user_id = $$result_href{'ad_user_id'} || '';
    my $stored_password = $$result_href{'password'} || '';

    if ($stored_password eq '') {
        return ("Account has no password.");
    }
    $ad_user_id || die "No ad_user_id for user '$username'!";


    # Check the password.  Adempiere uses plain text.  No, seriously.
    if ($stored_password ne $password) {
        return ("Incorrect password.");
    }


    # Fetch role configuration.
    $result_aref = $dbh->selectall_arrayref(
"SELECT DISTINCT r.name
FROM ad_user_roles ur
LEFT JOIN ad_role r
    ON r.ad_role_id = ur.ad_role_id
WHERE ur.isactive = 'Y' AND ur.ad_user_id = ? AND (ur.ad_client_id = ? OR ur.ad_client_id = 0) AND (ur.ad_org_id = ? OR ur.ad_org_id = 0)",
        { Slice => {} },
        $ad_user_id, $ad_client_id, $ad_org_id);

    my @role_array = map { my $n = $_->{name}; $n =~ s/[^a-z0-9]//gi; "role-$n" } @$result_aref;

    # Fetch window access configuration.
    $result_aref = $dbh->selectall_arrayref(
"SELECT DISTINCT w.name, wa.isreadwrite
FROM ad_window_access wa
LEFT JOIN ad_window w
    ON wa.ad_window_id = w.ad_window_id
LEFT JOIN ad_role r
    ON wa.ad_role_id = r.ad_role_id
LEFT JOIN ad_user_roles ur
    ON r.ad_role_id = ur.ad_role_id
WHERE
    ur.isactive = 'Y' AND wa.isactive = 'Y' AND ur.ad_user_id = ?",
        { Slice => {} },
        $ad_user_id);

    my @access_array = map { my $n = $_->{name}; $n =~ s/[^a-z0-9]//gi; (($_->{isreadwrite} eq 'Y') ? "write" : "read") . "-" . $n } @$result_aref;

    $result_aref = $dbh->selectall_arrayref(
"SELECT DISTINCT p.value, pa.isreadwrite
FROM ad_process_access pa
LEFT JOIN ad_process p
    ON pa.ad_process_id = p.ad_process_id
LEFT JOIN ad_role r
    ON pa.ad_role_id = r.ad_role_id
LEFT JOIN ad_user_roles ur
    ON r.ad_role_id = ur.ad_role_id
WHERE
    ur.isactive = 'Y' AND pa.isactive = 'Y' AND ur.ad_user_id = ?",
        { Slice => {} },
        $ad_user_id);

    my @process_access_array = map { my $n = $_->{value}; $n =~ s/[^a-z0-9]//gi; (($_->{isreadwrite} eq 'Y') ? "write" : "read") . "-" . $n } @$result_aref;

    my $group_list;

    # If we're given a relevant_groups parameter, restrict our groups to the intersection of the two lists.
    if ($login_parameters{'relevant_groups'}) {
        my %relevant_groups;
        map { $relevant_groups{$_} = 1; } (split ',', $login_parameters{'relevant_groups'});

        my @all_groups = (@role_array, @access_array, @process_access_array);
        my @intersection;
        foreach my $element (@all_groups) {
            push @intersection, $element if $relevant_groups{$element};
        }
        $group_list = join (",", @intersection);
    } else {
        # Otherwise combine role and table access.
        $group_list = join (",", @role_array, @access_array, @process_access_array);
    }

    # Find the IP address and name.  Note that reverse DNS lookup can sometimes take
    # a LONG TIME (up to 10 seconds or more).  In that case, the client is left waiting.
    # That's why this is configurable and default disabled.
    #
    my $remote_addr = $ENV{"HTTP_X_FORWARDED_FOR"} || $ENV{"HTTP_CLIENT_IP"} || $ENV{"REMOTE_ADDR"} || undef;
    my $reverse_dns = defined ($Jarvis::Config::yes_value {lc ($login_parameters{'reverse_dns'} || "no")});
    my $remote_host = undef;
    if ($remote_addr && $reverse_dns) {
        my @bytes = split(/\./, $remote_addr);

        if (scalar(@bytes) == 4) {
            my $packedaddr = pack("C4", @bytes);
            $remote_host = (gethostbyaddr($packedaddr, 2))[0];
        }
    }

    # Create a session row in Adempiere.
    $result_aref = $dbh->selectall_arrayref(
"INSERT INTO ad_session (
    ad_session_id, ad_client_id, ad_org_id, isactive,
    created, createdby, updated, updatedby,
    websession, remote_addr, remote_host,
    processed, description, ad_role_id, logindate)
VALUES (
    nextid_by_name ('AD_Session'), ?, ?, 'Y',
    now(), ?, now(), ?,
    null, ?, ?,
    'Y', 'Jarvis', null, now())
RETURNING
    ad_session_id",
        { Slice => {} },
        $ad_client_id, $ad_org_id, $ad_user_id, $ad_user_id, $remote_addr, $remote_host);

    my $ad_session_id = $$result_aref[0]->{ad_session_id} || die "Cannot determine ad_session_id";

    &Jarvis::Error::debug ($jconfig, "Session ID = '$ad_session_id'.");

    # Add safe params.
    my %safe_params = (
        '__ad_user_id' => $ad_user_id,
        '__ad_client_id' => $ad_client_id,
        '__ad_org_id' => $ad_org_id,
        '__ad_session_id' => $ad_session_id
    );

    &Jarvis::Error::debug ($jconfig, "Group list = '$group_list'.");
    return ("", $username, $group_list, \%safe_params);
}

1;
