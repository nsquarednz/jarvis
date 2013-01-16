###############################################################################
# Description:  Method to connect (if required) and return a database handle.
#               This allows you to only connect to the database if required -
#               since some requests don't actually need the database.
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
use strict;
use warnings;

package Jarvis::DB;

use DBI;
use Data::Dumper;

use Jarvis::Error;
use Jarvis::Hook;
use Jarvis::DB::SDP;

###############################################################################
# Global variables.
###############################################################################
#
# Note that global variables under mod_perl require careful consideration!
#
# Specifically, you must ensure that all variables which require 
# re-initialisation for each invocation will receive it.
#
# Cached database handles.  
# Hash {type}{name}
#
# They is safe because they are set to undef by the disconnect method, which is
# invoked whenever each Jarvis request finishes (either success or fail).
#
my %dbhs = ();

################################################################################
# Find the xml configuration object for a named db
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dbname - database name
#       $dbname - database type
#
# Returns:
#       $dbxml - xml configuration object for matching db handle
################################################################################
#
sub db_config {
    my ($jconfig, $dbname, $dbtype) = @_;

    # ensure our parameters are in order
    # sometimes we don't get strings but objects that auto-convert into strings, so our checks get a bit more complex
    $dbname = "default" unless defined $dbname && $dbname . '';
    $dbtype = "dbi" unless defined $dbtype && $dbtype . '';

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};

    # Find the specific database config we need.
    my @dbs = grep { (($_->{'name'}->content || 'default') eq $dbname) && (($_->{'type'}->content || 'dbi') eq $dbtype) } @{ $axml->{'database'} };
    (scalar @dbs) || die "No database with name '$dbname', type '$dbtype' is currently configured in Jarvis.";
    ((scalar @dbs) == 1) || die "Multiple databases with name '$dbname', type '$dbtype' are currently configured in Jarvis.";

    return $dbs[0];
}

################################################################################
# Connect to DB (if required) and return DBH.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               dbconnect           Database connection string
#               dbuser              Database username
#               dbpass              Database password
#
#       $dbname - Identify which database to connect to, default = "default"
#       $dbtype - Identify which database to connect to, default = "dbi"
#
# Returns:
#       1
################################################################################
#
sub handle {
    my ($jconfig, $dbname, $dbtype) = @_;

    $dbname || ($dbname = "default");
    $dbtype || ($dbtype = "dbi");

    if ($dbhs{$dbtype}{$dbname}) {
        &Jarvis::Error::debug ($jconfig, "Returning cached connection to database name = '$dbname', type = '$dbtype'");
        return $dbhs{$dbtype}{$dbname};
    }

    &Jarvis::Error::debug ($jconfig, "Making new connection to database name = '$dbname', type = '$dbtype'");

    # Configuration common to all database types.
    my $dbxml = &db_config($jconfig, $dbname, $dbtype);
    my $dbconnect = $dbxml->{'connect'}->content || '';
    my $dbusername = $dbxml->{'username'}->content || '';
    my $dbpassword = $dbxml->{'password'}->content || '';
    
    # Optional parameters, handled per-database type.
    my %parameters = ();
    if ($dbxml->{'parameter'}) {
        foreach my $parameter ($dbxml->{'parameter'}('@')) {
            &Jarvis::Error::debug ($jconfig, "DB Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
            $parameters {$parameter->{'name'}->content} = $parameter->{'value'}->content;
        }
    }
    my $post_connect = $dbxml->{'post_connect'};
    if ($post_connect) {
        # trim post_connect string
        $post_connect =~ s/^\s*//;
        $post_connect =~ s/\s*$//;
    }
    
    # Allow the hook to potentially modify some of these attributes.
    &Jarvis::Hook::pre_connect ($jconfig, $dbname, $dbtype, \$dbconnect, \$dbusername, \$dbpassword, \%parameters);

    &Jarvis::Error::debug ($jconfig, "DB Connect = '$dbconnect'");
    &Jarvis::Error::debug ($jconfig, "DB Username = '$dbusername'");
    &Jarvis::Error::debug ($jconfig, "DB Password = '$dbpassword'");
    
    # DBI is our "standard" type.
    &Jarvis::Error::debug ($jconfig, "Connecting to '$dbtype' database with handle named '$dbname'");
    if ($dbtype eq "dbi") {
        if (! $dbconnect) {
            $dbconnect = "dbi:Pg:dbname=" . $jconfig->{'app_name'};
            &Jarvis::Error::debug ($jconfig, "DB Connect = '$dbconnect' (default)");
        }
        my $dbh_attributes = {
            RaiseError => 1, 
            PrintError => 1, 
            AutoCommit => 1 
        };
        # Optional DBI connect attribute parameters, handled per-database type.
        if ($dbxml->{'dbh_attributes'}) {
            foreach my $attr ($dbxml->{'dbh_attributes'}->{'attribute'}('@')) {
                &Jarvis::Error::debug ($jconfig, "DBH custom attribute: " . $attr->{'name'}->content . " -> " . $attr->{'value'}->content);
                $dbh_attributes->{$attr->{'name'}->content} = $attr->{'value'}->content;
            }
        }

        my $dbh = $dbhs{$dbtype}{$dbname} = DBI->connect ($dbconnect, $dbusername, $dbpassword, $dbh_attributes) ||
            die "Cannot connect to DBI database '$dbname': " . DBI::errstr;
        if ($post_connect) {
            &Jarvis::Error::debug ($jconfig, "DB PostConnect = '$post_connect'");
            $dbh->do($post_connect) or die "Error Executing PostConnect: " . DBI::errstr;
        }
    # SDP is a SSAS DataPump pseudo-database.
    } elsif ($dbtype eq "sdp") {
        $dbconnect || die "Missing 'connect' parameter on SSAS DataPump database '$dbname'.";
        $dbhs{$dbtype}{$dbname} = Jarvis::DB::SDP->new ($jconfig, $dbconnect, $dbusername, $dbpassword, \%parameters);
        
    } else {
        die "Unsupported Database Type '$dbtype'.";
    }
    return $dbhs{$dbtype}{$dbname};
}

################################################################################
# Disconnect from DB (if required).  Under mod_perl we need to unassign the
# dbh, so that we get a fresh one next time, because our next request may be
# for a different application.
#
# Params:
#       $jconfig - Jarvis::Config object (not used)
#
# Returns:
#       1
################################################################################
#
sub disconnect {
    my ($jconfig) = @_;

    foreach my $dbtype (sort (keys %dbhs)) {
        foreach my $dbname (sort (keys %{ $dbhs{$dbtype} })) {
            &Jarvis::Error::debug ($jconfig, "Disconnecting from database type = '$dbtype', name = '$dbname'.");
            $dbhs{$dbtype}{$dbname} && $dbhs{$dbtype}{$dbname}->disconnect();
            delete $dbhs{$dbtype}{$dbname};
        }
    }
}

1;
