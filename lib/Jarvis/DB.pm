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

use DBI;

package Jarvis::DB;

use Jarvis::Error;

###############################################################################
# PRIVATE VARIABLES
###############################################################################
#

my $dbh = undef;

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
# Returns:
#       1
################################################################################
#
sub handle {
    my ($jconfig) = @_;

    $dbh && return $dbh;

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    my $dbxml = $axml->{'database'} || die "No 'database' config present.  Cannot connect to DB.";

    my $dbconnect = $dbxml->{'connect'}->content || "dbi:Pg:dbname=" . $jconfig->{'app_name'};
    my $dbusername = $dbxml->{'username'}->content || '';
    my $dbpassword = $dbxml->{'password'}->content || '';

    &Jarvis::Error::debug ($jconfig, "DB Connect = '$dbconnect'");
    &Jarvis::Error::debug ($jconfig, "DB Username = '$dbusername'");
    &Jarvis::Error::debug ($jconfig, "DB Password = '$dbpassword'");

    $dbh = DBI->connect ($dbconnect, $dbusername, $dbpassword, { RaiseError => 1, PrintError => 1, AutoCommit => 1 }) ||
        die "Cannot connect to database. " . DBI::errstr;

    return $dbh;
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

    $dbh && $dbh->disconnect();
    $dbh = undef;
}

1;