#!/usr/bin/perl
###############################################################################
# Description:
#       General purpose utility function for providing JSON or XML
#       interface to server-side database tables.  Should be compatible
#       with ExtJS (tested with JSON) and Flex (tested with XML).
#
#       Server-side configuration defines the SQL.  Sessions are managed
#       with CGI::Session.  A pluggable authentication approach allows for
#       different login rules.
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
use strict;
use warnings;

use Carp;
use CGI;

use lib "/opt/jarvis/lib";

use Jarvis::Error;
use Jarvis::Config;
use Jarvis::Dataset;
use Jarvis::Status;

package Main;

$Main::cgi = new CGI();
$Main::jarvis_etc = $ENV{'JARVIS_ETC'} || "/opt/jarvis/etc";
%Main::args = ();

$Carp::CarpLevel = 1;

###############################################################################
# Setup error handler.
###############################################################################
#
sub Handler {
    my ($msg) = @_;

    # Return error.  Note that we do not print stack trace to user, since
    # that is a potential security weakness.
    print $Main::cgi->header("text/plain");
    print $Main::cgi->url () . "\n";
    print $msg;

    # Print to error log.  Include stack trace if debug is enabled.
    print STDERR ($Main::args{'debug'} ? Carp::longmess $msg : Carp::shortmess $msg);
    exit 0;
}

###############################################################################
# Main Program
###############################################################################
#
MAIN: {
    $SIG{__WARN__} = sub { die shift };
    $SIG{__DIE__} = \&Main::Handler;

    ###############################################################################
    # AppName: (mandatory parameter)
    ###############################################################################
    #
    my $app_name = $Main::cgi->param ('app') || die "Missing mandatory parameter 'app'!\n";
    ($app_name =~ m/^\w+$/) || die "Invalid characters in parameter 'app'\n";

    $Main::args{'cgi'} = $Main::cgi;
    $Main::args{'app_name'} = $app_name;
    $Main::args{'etc_dir'} = "$Main::jarvis_etc";

    &Jarvis::Config::Setup (\%Main::args);

    ###############################################################################
    # Action: "status", "fetch", "update".
    ###############################################################################
    #
    # Must have an action.
    $Main::args{'action'} = $Main::cgi->param ('action') || die "Missing mandatory parameter 'action'!\n";
    ($Main::args{'action'} =~ m/^\w+$/) || die "Invalid characters in parameter 'action'\n";

    my $return_text = '';

    # Status.  I.e. are we logged in?
    if ($Main::args{'action'} eq "status") {

        $return_text = &Jarvis::Status::Report (%Main::args);

    # Fetch.  I.e. get some data.
    } elsif ($Main::args{'action'} eq "fetch") {

        $return_text = &Jarvis::Dataset::Fetch (%Main::args);

    # Store.  I.e. alter some data.
    } elsif ($Main::args{'action'} eq "store") {

        $return_text = &Jarvis::Dataset::Store (%Main::args);

    } else {
        die "Unsupported action '" . $Main::args{'action'} . "'!\n";
    }

    my $cookie = CGI::Cookie->new (-name => $Main::args{'sname'}, -value => $Main::args{'sid'});
    print $Main::cgi->header(-type => "text/plain", -cookie => $cookie);
    print $return_text;

    ###############################################################################
    # Cleanup.
    ###############################################################################
    #
    $Main::args{'dbh'} && $Main::args{'dbh'}->disconnect();
}

1;
