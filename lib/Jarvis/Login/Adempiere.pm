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
#            <parameter name="allowed_groups" value="SuperUser,Admin"/>
#            <parameter name="role_name_pattern" value="Role_Prefix%"/>
#        </login>
#        ...
#    </app>
#
#       You can set role_name_pattern to restrict users who can login
#       to matching user roles.
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

package Jarvis::Login::Adempiere;

use Jarvis::Error;

###############################################################################
# Utility Functions
###############################################################################

# converts a list of strings with * wildcard into a single perl regular expression string
sub list_regexp {
    my @list = @_;
    my $regexp = '';
    foreach my $match (@list) {
        # escape all potential meta-characters
        $match =~ s/([^\w\s\*])/\\$1/g;
        # any whitespace sequence will match any other
        $match =~ s/\s+/\\s+/g;
        # translate * wildcard
        $match =~ s/\*/.*/g;
        # append to regexp
        $regexp .= (length($regexp) > 0 ? "|$match" : $match);
    }
    return $regexp;
}

# prints a long list of strings by splitting it into groups
# individual values are separated by $sep, groups by \n
sub list_print($$@) {
    my ($group_size, $sep, @list) = @_;

    my @groups = ();
    for (my $i=0; $i < scalar(@list); $i += $group_size) {
        my $last = $i + $group_size - 1;
        $last = scalar(@list) - 1 unless $last < scalar(@list);
        my @group = @list[$i .. $last];
        push @groups, \@group;
    }
    return join("\n", map { join($sep, @$_) } @groups);
}

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

    # login parameters
    my $client_name = $login_parameters{'client_name'};
    my $org_name = $login_parameters{'org_name'};
    my $dbname = $login_parameters{'dbname'} || 'default';
    my $allowed_groups = $login_parameters{'allowed_groups'} || '';
    my $role_name_pattern = $login_parameters{'role_name_pattern'} || '%';

    my $dbh = &Jarvis::DB::handle ($jconfig, $dbname);

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
    $result_aref = $dbh->selectall_arrayref("SELECT DISTINCT u.ad_user_id, password FROM ad_user u JOIN ad_user_roles ur ON u.ad_user_id=ur.ad_user_id JOIN ad_role r ON ur.ad_role_id=r.ad_role_id WHERE u.name = ? AND u.isactive = 'Y' AND ur.isactive='Y' AND (u.ad_client_id = ? OR u.ad_client_id = 0) AND (u.ad_org_id = ? OR u.ad_org_id = 0) AND r.name LIKE ?", { Slice => {} }, $username, $ad_client_id, $ad_org_id, $role_name_pattern);
    if ((scalar @$result_aref) < 1) {
        return ("User '$username' not known/active.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    $result_href = $$result_aref[0];
    my $ad_user_id = $$result_href{'ad_user_id'} || '';
    &Jarvis::Error::debug ($jconfig, "User ID = '$ad_user_id'.");
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
        my $relevant_groups_regexp = list_regexp(split(',', $login_parameters{'relevant_groups'}));
        &Jarvis::Error::debug ($jconfig, "relevant_groups_regexp=$relevant_groups_regexp");
        my @all_groups = (@role_array, @access_array, @process_access_array);
        &Jarvis::Error::dump ($jconfig, "role_array=\n" . list_print(100, ',', @role_array));
        &Jarvis::Error::dump ($jconfig, "access_array=\n" . list_print(100, ',', @access_array));
        &Jarvis::Error::dump ($jconfig, "process_access_array=\n" . list_print(100, ',', @process_access_array));
        my @intersection;
        foreach my $element (@all_groups) {
            push @intersection, $element if $element =~ /$relevant_groups_regexp/;
        }
        $group_list = join (",", @intersection);
    } else {
        # Otherwise combine role and table access.
        $group_list = join (",", @role_array, @access_array, @process_access_array);
    }

    # we got the group list, check if user is allowed
    if ($allowed_groups) {
        my $allowed_groups_regexp = list_regexp($allowed_groups);
        unless ( scalar(grep { $_ =~ /$allowed_groups_regexp/ } split(',', $group_list)) ) {
            &Jarvis::Error::debug ($jconfig, "No allowed group for user '$username'.");
            return ("Login Denied.");
        }
    }

    # Find the IP address and name.  Note that reverse DNS lookup can sometimes take
    # a LONG TIME (up to 10 seconds or more).  In that case, the client is left waiting.
    # That's why this is configurable and default disabled.
    #
    my $remote_addr = $jconfig->{'client_ip'};
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
