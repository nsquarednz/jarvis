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
sub Handle {
    my ($jconfig) = @_;

    $dbh && return $dbh;

    $jconfig->{'dbconnect'} || &Jarvis::Error::MyDie ($jconfig, "No 'dbconnect' parameter specified.  Cannot connect to DB.");
    &Jarvis::Error::Debug ($jconfig, "DB Connect = " . $jconfig->{'dbconnect'});
    &Jarvis::Error::Debug ($jconfig, "DB Username = " . $jconfig->{'dbusername'});
    &Jarvis::Error::Debug ($jconfig, "DB Password = " . $jconfig->{'dbpassword'});

    $dbh = DBI->connect ($jconfig->{'dbconnect'}, $jconfig->{'dbusername'}, $jconfig->{'dbpassword'}) ||
        &Jarvis::Error::MyDie ("Cannot connect to database. " . DBI::errstr);
}

################################################################################
# Disconnect from DB (if required).
#
# Params:
#       $jconfig - Jarvis::Config object (not used)
#
# Returns:
#       1
################################################################################
#
sub Disconnect {
    my ($jconfig) = @_;

    $dbh && $dbh->disconnect();
}

1;