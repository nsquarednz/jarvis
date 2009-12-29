#!/usr/bin/perl
###############################################################################
# Descript: This script populates the 'calendar' and other similar tables in 
#           the tracker database. These tables can be regenerated at any time
#           as their content is used for reporting and analysis purposes, and
#           is not depedant on specific system behaviour.
#
# Licence:
#       This file is part of the Jarvis Tracker application.
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
#       This software is Copyright 2008 by Jamie Love.
###############################################################################
use strict;
use warnings;

use DBI;
use Date::Calc qw (Delta_Days Add_Delta_Days Date_to_Time Day_of_Week Week_of_Year); # TODO Add to the documentation
use Date::Format;

my $c = 0;
my @startDate = ( 2008, 1, 1 );
my $daysToInclude = Delta_Days (@startDate,
                                2020, 1, 1);

my $dbh = DBI->connect ("dbi:SQLite:dbname=tracker.db", "", "" ) || die "Unable to open tracker database 'tracker.db': " .DBI::errstr;

$dbh->begin_work() || die;

#
# This section populates the 'calendar' table.
#
my $sth;

$sth = $dbh->prepare ("DELETE FROM calendar") || die "Unable to prepare statement to delete all rows from the 'calendar' table: " . DBI::errstr;

$sth->execute() || die "Unable to execute statement to delete all rows from the 'calendar' table: " . DBI::errstr;
$sth->finish;

$sth = $dbh->prepare ("INSERT INTO calendar (the_date, is_weekday, year, quarter, month, day, day_of_week, week) VALUES (?, ?, ?, ?, ?, ?, ?, ?)") || die "Unable to prepare statement to insert a row into the 'calendar' table: " . DBI::errstr;;

while ($c <= $daysToInclude) {
    my @day = Add_Delta_Days (@startDate, $c);
    $c++;

    my @bindVars = (
        Date_to_Time (@day, 0, 0, 0) / 86400.0 + 2440587.5
        , (Day_of_Week (@day) < 6 ? 1 : 0)
        , $day[0]
        , ($day[1] < 4 ? 1 : ($day[1] < 7 ? 2 : ($day[1] < 10 ? 3 : 4)))
        , $day[1]
        , $day[2]
        , Day_of_Week (@day)
        , (Week_of_Year (@day))[0]
    );

    #print ((join ",", @bindVars) . "\n");
    print ".";
    if ($c % 365 == 0) {
        print "\n";
    }

    $sth->execute (@bindVars) || die "Unable to insert calendar day into calendar table: " . DBI::errstr;
}

$sth->finish;

#
# This section populates the 'day_interval' table.
#
$sth = $dbh->prepare ("DELETE FROM day_interval") || die "Unable to prepare statement to delete all rows from the 'day_interval' table: " . DBI::errstr;
$sth->execute() || die "Unable to execute statement to delete all rows from the 'day_interval' table: " . DBI::errstr;
$sth->finish;

$sth = $dbh->prepare ("INSERT INTO day_interval (interval, hour, hour_minute, is_minute, is_five_minute, is_fifteen_minute) VALUES (?, ?, ?, ?, ?, ?)") || die "Unable to prepare statement to insert a row into the 'day_interval' table: " . DBI::errstr;;

my $totalIntervals = 60 * 24 - 1;
$c = 0;
while ($c <= $totalIntervals) {
    my @bindVars = (
        $c * 1.0 / (24 * 60.0),
        , int($c / 60)
        , $c % 60
        , 1
        , $c % 5 == 0 ? 1 : 0
        , $c % 15 == 0 ? 1 : 0
    );

    #print ((join ",", @bindVars) . "\n");

    $sth->execute (@bindVars) || die "Unable to insert interval into day_interval table: " . DBI::errstr;
    $c++;
}

$sth->finish;

$dbh->commit;
