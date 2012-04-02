###############################################################################
# Description:  Performs tracking functions for Jarvis.  These are written
#               to the tracking database with SQLite.  We track requests and
#               errors.
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

use Time::HiRes;
use Time::Local;
use XML::Smart;

package Jarvis::Tracker;

use Jarvis::Text;
use Jarvis::Error;

###############################################################################
# Global variables.
###############################################################################
#
# Note that global variables under mod_perl require careful consideration!
#
# Specifically, you must ensure that all variables which require 
# re-initialisation for each invocation will receive it.
#
# Tracker DB handle.  Cached for efficiency.
#
# It is safe because it is set to undef by the disconnect method, which is
# invoked whenever each Jarvis request finishes (either success or fail).
#
my $tdbh = undef;

################################################################################
# Connect to tracker DB (if required) and return DBH.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               tracker
#
# Returns:
#       1
################################################################################
#
sub handle {
    my ($jconfig) = @_;

    $tdbh && return $tdbh;

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    my $tracker = $axml->{'tracker'};
    if (!$tracker) {
        &Jarvis::Error::log ($jconfig, "No 'tracker' config present. Won't connect to tracker DB.");
        return;
    }

    $tdbh = &Jarvis::DB::handle ($jconfig, 'tracker');

    return $tdbh;
}

################################################################################
# Disconnect from tracker DB (if required).  Under mod_perl we need to unassign
# the dbh, so that we get a fresh one next time, because our next request may be
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

    $tdbh && $tdbh->disconnect();
    $tdbh = undef;
}

################################################################################
# Start of tracking.  Call at the start of the request handling.  All we do
# here is record the start time.
#
# Params:
#       $jconfig - Jarvis::Config object
#
# Returns:
#       1.
################################################################################
#
sub start {
    my ($jconfig) = @_;

    # Start time.
    $jconfig->{'tstart'} = [Time::HiRes::gettimeofday];
}

# format time as Unix Epoch time in Julian date format
sub timestamp_julian($) {
    my ($time) = @_;
    return (($$time[0] + $$time[1] / 1000000) / 86400.0 ) + 2440587.5;
}

# format time as sql timestamp
sub timestamp_sql($) {
    my ($time) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime($time);
    my $timestamp_sql = sprintf('%04d-%02d-%02d %02d:%02d:%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
    return $timestamp_sql;
}

################################################################################
# End of tracking.  Call when all is done.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               tracker
#
# Returns:
#       1.
################################################################################
#
sub finish {
    my ($jconfig) = @_;

    # Are we tracking requests?
    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};

    my $tracker = $axml->{'tracker'};
    $tracker || return;

    my $requests = defined ($Jarvis::Config::yes_value {lc ($tracker->{'requests'}->content || "no")});
    $requests || return;

    # Get the handle to the tracker database.
    my $tdbh = &Jarvis::Tracker::handle ($jconfig);
    $tdbh || return;

    # Interval in ms since start time.
    my $sid = $jconfig->{'sid'};
    my $debug_level = $jconfig->{'dump'} ? 2 : ($jconfig->{'debug'} ? 1 : 0);
    my $app_name = $jconfig->{'app_name'};
    my $username = $jconfig->{'username'};
    my $group_list = $jconfig->{'group_list'};
    my $dataset = $jconfig->{'dataset_name'};
    my $dataset_type = $jconfig->{'dataset_type'};
    my $action =  $jconfig->{'action'};
    my $in_nrows = $jconfig->{'in_nrows'} || 0;
    my $out_nrows = $jconfig->{'out_nrows'} || 0;

    # Parameters.  Discard system special (__abc...).  Separate with colons.  Escape special chars.
    my %params = $jconfig->{'params_href'} ? %{ $jconfig->{'params_href'} } : ();
    my $param_string = join (':', map {
        my $pval = ($params{$_} || '');
        $pval =~ s/\\/\\\\/g;
        $pval =~ s/=/\\=/g;
        $pval =~ s/:/\\:/g;
        "$_" . "=" . $pval
    } grep { ! m/^__/ } sort (keys %params));

    # Julian time of request start.
    my $tstart = $jconfig->{'tstart'};
    my $start_time = timestamp_sql($tstart);
    my $duration_ms = int (Time::HiRes::tv_interval ($tstart) * 1000);

    # Perform the database insert.
    my $sth = $tdbh->prepare (
"INSERT INTO request (
    sid, debug_level, app_name, username, group_list, dataset, dataset_type, action,
    params, in_nrows, out_nrows, start_time, duration_ms)
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)");

    if (! $sth) {
        &Jarvis::Error::log ($jconfig, "Cannot prepare tracker request INSERT: " . $tdbh->errstr);
        return;
    }

    my $rv = $sth->execute ($sid, $debug_level, $app_name, $username, $group_list, $dataset, $dataset_type,
        $action, $param_string, $in_nrows, $out_nrows, $start_time, $duration_ms);

    if (! $rv) {
        &Jarvis::Error::log ($jconfig, "Cannot execute tracker request INSERT: " . $tdbh->errstr);
        $sth->finish ();
        return;
    }

    $sth->finish ();
}

################################################################################
# An error has occured, record it in the "error" table.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               tracker
#       $http_response_code - the HTTP response code that will be or has been
#                             used for the requests that caused the error (e.g.
#                             401). Only the number is required - not the text
#                             description of the code, though text after the
#                             initial number is discarded.
#       $message - Error text that was printed to STDERR.
#
# Returns:
#       1.
################################################################################
#
sub error {
    my ($jconfig, $http_response_code, $message) = @_;

    # Are we tracking errors?
    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};

    my $tracker = $axml->{'tracker'};
    $tracker || return;

    my $errors = defined ($Jarvis::Config::yes_value {lc ($tracker->{'errors'}->content || "no")});
    $errors || return;

    # Get the handle to the tracker database.
    my $tdbh = &Jarvis::Tracker::handle ($jconfig);
    $tdbh || return;

    # Interval in ms since start time.
    my $sid = $jconfig->{'sid'};
    my $app_name = $jconfig->{'app_name'};
    my $username = $jconfig->{'username'};
    my $group_list = $jconfig->{'group_list'};
    my $dataset = $jconfig->{'dataset_name'};
    my $action =  $jconfig->{'action'};

    # The 'store' method made a copy of this for us, thankfully.
    my $post_body = &Jarvis::Dataset::get_post_data ($jconfig);

    # Parameters.  Discard system special (__abc...).  Separate with colons.  Escape special chars.
    my %params = $jconfig->{'params_href'} ? %{ $jconfig->{'params_href'} } : ();
    my $param_string = join (':', map {
        my $pval = ($params{$_} || '');
        $pval =~ s/\\/\\\\/g;
        $pval =~ s/=/\\=/g;
        $pval =~ s/:/\\:/g;
        "$_" . "=" . $pval
    } grep { ! m/^__/ } sort (keys %params));

    # Julian time of request start.
    my $tstart = $jconfig->{'tstart'};
    my $start_time = timestamp_sql($tstart);

    # Get error number
    $http_response_code =~ s/^([0-9]+).*$/$1/;
    $http_response_code = undef if !$http_response_code =~ /^[0-9]+$/;

    # Perform the database insert.
    my $sth = $tdbh->prepare (
"INSERT INTO error (
    sid, app_name, username, group_list, dataset, action,
    params, post_body, message, start_time, http_response_code)
VALUES (?,?,?,?,?,?,?,?,?,?,?)");

    if (! $sth) {
        &Jarvis::Error::log ($jconfig, "Cannot prepare tracker error INSERT: " . $tdbh->errstr);
        return;
    }

    my $rv = $sth->execute ($sid, $app_name, $username, $group_list, $dataset,
        $action, $param_string, $post_body, $message, $start_time, $http_response_code);

    if (! $rv) {
        &Jarvis::Error::log ($jconfig, "Cannot execute tracker error INSERT: " . $tdbh->errstr);
        $sth->finish ();
        return;
    }

    $sth->finish ();
}

################################################################################
# We have logged in a new session, or failed to log in.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               tracker
#
# Returns:
#       1.
################################################################################
#
sub login {
    my ($jconfig, $message) = @_;

    # Are we tracking logins?
    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};

    my $tracker = $axml->{'tracker'};
    $tracker || return;

    my $logins = defined ($Jarvis::Config::yes_value {lc ($tracker->{'logins'}->content || "no")});
    $logins || return;

    # Get the handle to the tracker database.
    my $tdbh = &Jarvis::Tracker::handle ($jconfig);
    $tdbh || return;

    # Interval in ms since start time.
    my $sid = $jconfig->{'sid'};
    my $app_name = $jconfig->{'app_name'};
    my $username = $jconfig->{'username'} || $jconfig->{'offered_username'};
    my $logged_in = $jconfig->{'logged_in'};
    my $error_string = $jconfig->{'error_string'};
    my $group_list = $jconfig->{'group_list'};
    my $actual_ip = $jconfig->{'client_ip'};

    # Julian time of request start.
    my $tstart = $jconfig->{'tstart'};
    my $start_time = timestamp_sql($tstart);

    # Perform the database insert.
    my $sth = $tdbh->prepare (
"INSERT INTO login (
    sid, app_name, username, logged_in, error_string, group_list, address, start_time)
VALUES (?,?,?,?,?,?,?,?)");

    if (! $sth) {
        &Jarvis::Error::log ($jconfig, "Cannot prepare tracker login INSERT: " . $tdbh->errstr);
        return;
    }

    my $rv = $sth->execute ($sid, $app_name, $username, $logged_in, $error_string, $group_list, $actual_ip, $start_time);

    if (! $rv) {
        &Jarvis::Error::log ($jconfig, "Cannot execute tracker login INSERT: " . $tdbh->errstr);
        $sth->finish ();
        return;
    }

    $sth->finish ();
}

1;
