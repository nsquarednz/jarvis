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
#       %args - The global settings hash.
#
#   You Must SPECIFY
#           $args{'dbconnect'}          Database connection string
#           $args{'dbuser'}             Database username
#           $args{'dbpass'}             Database password
#
# Returns:
#       1
################################################################################
#
sub Handle {
    my (%args) = @_;

    $dbh && return $dbh;

    $args{'dbconnect'} || &Jarvis::Error::MyDie ("No 'dbconnect' parameter specified.  Cannot connect to DB.", %args);
    &Jarvis::Error::Log ("DB Connect = " . $args{'dbconnect'}, %args);
    &Jarvis::Error::Log ("DB Username = " . $args{'dbusername'}, %args);
    &Jarvis::Error::Log ("DB Password = " . $args{'dbpassword'}, %args);

    $dbh = DBI->connect ($args{'dbconnect'}, $args{'dbusername'}, $args{'dbpassword'}) ||
        &Jarvis::Error::MyDie ("Cannot connect to database. " . DBI::errstr);
}

################################################################################
# Disconnect from DB (if required).
#
# Params:
#       %args - The global settings hash.
#
# Returns:
#       1
################################################################################
#
sub Disconnect {
    my (%args) = @_;

    $dbh && $dbh->disconnect();
}

1;