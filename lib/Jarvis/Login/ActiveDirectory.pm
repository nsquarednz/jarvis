
###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.  This module checks usernames
#       and passwords via ActiveDirectory (Microsoft's LDAP Implementation).
#
#       Refer to the documentation for the "check" function for how
#       to configure your <application>.xml to use this login module.
#
# Licence:
#       This file is part of the Jarvis WebApp/LDAP gateway utility.
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

package Jarvis::Login::ActiveDirectory;

use Net::LDAP;

use Jarvis::Error;
use Jarvis::Login::Adempiere;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing user/pass.  We validate this by checking a table in the
# currently open database.  The user and pass columns are both within this same
# table.
#
# To use this method, specify the following login parameters.
#
#    <app format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::ActiveDirectory">
#           <parameter name="server"         value="<server-address>"/>
#           <parameter name="port"           value="389"/>
#           <parameter name="bind_username"  value="<bind-username>"/>
#           <parameter name="bind_password"  value="<bind-password>"/>
#           <parameter name="base_object"    value="dc=nsquared,dc=nz"/>
#           <parameter name="allowed_groups" value="SuperUser,Admin"/>
#           <parameter name="search_filter"  value="samaccountname"/>
#           <parameter name="use_tls"        value="1"/>
#           <parameter name="group_lookup"   value="memberOf"/>
#        </login>
#        ...
#    </app>
#
#       server            : Address of server.  Required.
#       port              : Port for server.  Default 389.
#       bind_username     : Username to bind to server for search.
#       bind_password     : Password to bind to server for search.
#       base_object       : Root of the search tree for user lookup.
#       no_password       : Don't validate the password.  Only check user details.
#       allowed_groups    : Only allow login for users belonging to one of these groups. Optional.
#       search_filter     : Override the search filter name to use for user lookup. Optional. Default samaccountname.
#       use_tls           : Whether to utilize LDAP TLS connectivity. Optional. Default 0.
#       group_lookup      : The mechanism to determine group membership. Supports "memberOf" or "query". Optional. Default "memberOf".
#       group_base        : Root of the search tree for group lookup.
#       group_object_class: The object class to search for when determining group membership. Optional. Default "groupOfNames".
#       group_member_class: The member class to lookup when attempting to determien group membership. Optional. Default "member".
#       group_member_bind : The type of lookup object to use to bind when querying groups. Optional. Default "dn".
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi
#
#       $username - The offered username
#       $password - The offered password
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::ActiveDirectory::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # Our user name login parameters are here...
    my $server             = $login_parameters{server};
    my $port               = $login_parameters{port}               || 389;
    my $bind_username      = $login_parameters{bind_username}      || '';
    my $bind_password      = $login_parameters{bind_password}      || '';
    my $base_object        = $login_parameters{base_object}        || '';
    my $no_password        = $login_parameters{no_password}        || 0;
    my $allowed_groups     = $login_parameters{allowed_groups}     || '';
    my $search_filter      = $login_parameters{search_filter}      || 'samaccountname';
    my $use_tls            = $login_parameters{use_tls}            || 0;
    my $group_lookup       = $login_parameters{group_lookup}       || 'memberOf';
    my $group_object_class = $login_parameters{group_object_class} || 'groupOfNames';
    my $group_member_class = $login_parameters{group_member_class} || 'member';
    my $group_member_bind  = $login_parameters{group_member_bind}  || 'dn';
    my $group_base         = $login_parameters{group_base};

    # No info?
    $username || return ("No username supplied.");
    $password || $no_password || return ("No password supplied.");

    # Sanity check on config.
    $server      || return ("Missing 'server' configuration for Login module ActiveDirectory.");
    $base_object || return ("Missing 'base_object' configuration for Login module ActiveDirectory.");
    ($group_lookup eq 'query' && ! defined ($group_base)) &&  return ("Missing 'group_base' configuration for 'query' groups mode for Login module ActiveDirectory");

    # Do that ActiveDirectory thing.  Connect first.  AD uses default LDAP port 389.
    &Jarvis::Error::debug ($jconfig, "Connecting to ActiveDirectory Server: '$server:$port'.");
    my $ldap = Net::LDAP->new ($server, port => $port) || die "Cannot connect to '$server' on port $port\n";

    # Configuration requires us to use TLS.
    if ($use_tls) {
        # Start a TLS session on the LDAP object.
        $ldap->start_tls ();
    }

    # Bind with a password.
    #   Protocol = 3 (Default)
    #   Authentication = Simple (Default)
    #
    &Jarvis::Error::debug ($jconfig, "Binding to ActiveDirectory Server: '$server:$port' as '$bind_username'.");
    my $mesg = $ldap->bind ($bind_username, password => $bind_password);

    $mesg->code && die "Bind to server '$server:$port' failed with " . $mesg->code . " '" . $mesg->error . "'\n";

    # Now search on our base object.
    #   Scope = Whole Tree (Default)
    #   Deref = Always
    #   Types Only = False (default)
    #
    &Jarvis::Error::debug ($jconfig, "Searching for $search_filter = '$username'.");

    # Determine attributes to query for. We have some base values.
    my $query_attributes = [
        'mail'
        , 'uid'
    ];

    # If we are using memberOf group looksup lets ensure we request it.
    if ($group_lookup eq 'memberOf') {
        push @{$query_attributes}, 'memberOf';
    }

    $mesg = $ldap->search (
        base   => $base_object,
        deref  => 'always',
        attrs  => $query_attributes,
        filter => "($search_filter=$username)"
    );

    # Check that we got success, and exactly one entry.  We can't handle more than
    # one account with the same login ID.
    #
    $mesg->code && die "Search for '$username' failed with " . $mesg->code . " '" . $mesg->error . "'\n";
    $mesg->count || return "User '$username' not known to ActiveDirectory.";
    ($mesg->count == 1) || return "User '$username' ambiguous in ActiveDirectory.";

    # Get the entry and see who it's for.
    #
    my $entry = $mesg->entry (0);
    my $dn    = $entry->dn ();
    my $uid   = $entry->get_value ('uid');

    &Jarvis::Error::debug ($jconfig, "User DN '$dn'");


    # The way we fetch groups depends on how we are configured.
    my $group_list = '';

    # If the lookup model is 'memberOf' we check the previous request and look for a 'memberOf' entry.
    if ($group_lookup eq 'memberOf') {

        # Now look at the memberOf attribute of this account.  If they don't belong to
        # any groups, that's strange, but probably not impossible.  We let the application
        # sort that out.
        #
        # Build up our group_list, which consists only of the "CN" or "cn" part of the groups.  Actually,
        # a comma separator was probably a poor choice of separator in our group_list, since
        # full LDAP group specifications use commas for the CN, OU, DC components.  Oh well.
        #
        my @groups = $entry->get_value ('memberOf');

        foreach my $group (@groups) {
            &Jarvis::Error::debug ($jconfig, "Checking group '$group'.");
            if ($group =~ m/^CN=([^,]+),/i) {
                my $cn_group = $1;
                &Jarvis::Error::debug ($jconfig, "Identified as member of '$cn_group'.");
                $group_list .= ($group_list ? "," : "") . $cn_group;
            } else {
                &Jarvis::Error::log ($jconfig, "User '$username' is memberOf group with unsupported name syntax." );
            }
        }

    # If we are using a 'query' lookup then we need to perform an additional search against
    # the users search filtered username and look for group membership.
    } elsif ($group_lookup eq 'query') {

        # Determien the search term. This depends on what we're binding to.
        my $group_search_user_filter;
        if ($group_member_bind eq 'dn') {
            $group_search_user_filter = $dn;

        } elsif ($group_member_bind eq 'uid') {
            $uid || return "User '$username' does not have an associated UID.";
            $group_search_user_filter = $uid;

        } else {
            die "Unsupported Group Member Bind: '$group_member_bind'\n";
        }

        # Search the configured group base object looking for mapped group objects for our username.
        &Jarvis::Error::debug ($jconfig, "Searching for groups belonging to $search_filter = '$username'.");
        $mesg = $ldap->search (
            base   => $group_base,
            deref  => 'always',
            # Request the CN for our group so we don't have to parse it out.
            attrs  => [
                'cn'
            ],
            # Check for the requested group object class matching the DN against the object class member property.
            filter => "(&(objectClass=$group_object_class)($group_member_class=$group_search_user_filter))"
        );

        # Check for failure.
        $mesg->code && die "Search for '$username' failed with " . $mesg->code . " '" . $mesg->error . "'\n";

        # We might have no group or multiple. Each group will be in its own response object. Parse each entry.
        foreach $entry ($mesg->entries) {
            my $group_cn = $entry->get_value ('cn') || die "Receieved group mapping that did not contain a 'CN'.\n";
            $group_list .= ($group_list ? "," : "") . $group_cn;
        }

    } else {
        die "Unsupported 'group_lookup' '$group_lookup'\n";
    }

    $ldap->unbind ();

    # we got the group list, check if user is allowed
    if ($allowed_groups) {
        my $allowed_groups_regexp = Jarvis::Login::Adempiere::list_regexp($allowed_groups);
        unless ( scalar(grep { $_ =~ /$allowed_groups_regexp/ } split(',', $group_list)) ) {
            &Jarvis::Error::debug ($jconfig, "No allowed group for user '$username'.");
            return ("Login Denied.");
        }
    }

    # Did we get an email address?  Store it if we did.
    $jconfig->{'email'} = $entry->get_value ('mail');
    &Jarvis::Error::debug ($jconfig, "Mail Address is '" . ($jconfig->{'email'} || '') . "'.");

    # Sometimes we don't want to check the password.
    if ($no_password) {
        &Jarvis::Error::debug ($jconfig, "Skipping Password Check (as per configuration).");
        return ("", $username, $group_list);
    }

    # Reconnect and check the password.
    &Jarvis::Error::debug ($jconfig, "Connecting to ActiveDirectory Server: '$server:$port'.");
    $ldap = Net::LDAP->new ($server, port => $port) || die "Cannot connect to '$server' on port $port\n";

    # Configuration requires us to use TLS.
    if ($use_tls) {
        # Start a TLS session on the LDAP object.
        $ldap->start_tls ();
    }

    $mesg = $ldap->bind ($dn, password => $password);
    if ($mesg->code == 49) {
        &Jarvis::Error::debug ($jconfig, "Password check failed for user '$username'.");
        return ("Incorrect password.");
    }
    $mesg->code && die "Bind to server '$server:$port' failed with " . $mesg->code . " '" . $mesg->error . "'\n";
    $ldap->unbind ();

    # Store the username information against the session
    $jconfig->{session}->param ('external_user_id'       , $username);
    $jconfig->{session}->param ('external_user_principle', $username);

    &Jarvis::Error::debug ($jconfig, "Password check succeeded for user '$username'.");
    return ("", $username, $group_list);
}

1;
