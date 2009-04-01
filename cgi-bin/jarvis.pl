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
use Jarvis::Login;
use Jarvis::Dataset;
use Jarvis::Status;
use Jarvis::Exec;
use Jarvis::Plugin;
use Jarvis::DB;

package Main;

# This is our CGI object.  We pass it into our Jasper::Config, but we also
# use it in our "die" handler.
my $cgi = new CGI;

# This is our Jasper Config object which is passed around everywhere, and is
# used in our "die" handler so it needs to be module wide.
my $jconfig = undef;

$Carp::CarpLevel = 1;

###############################################################################
# Setup error handler.
###############################################################################
#
sub handler {
    my ($msg) = @_;

    # Truncate any thing after a null-TERM.  This is because LDAP error
    # messages sometimes put some junk in, which means that the browser
    # thinks the error is binary, and doesn't display it.
    $msg =~ s/\x00.*$//;
    $msg =~ s/\s+//;

    # Return error.  Note that we do not print stack trace to user, since
    # that is a potential security weakness.
    print $cgi->header("text/plain");
    print $cgi->url () . "\n";
    print $msg;

    # Print to error log.  Include stack trace if debug is enabled.
    print STDERR ($jconfig->{'debug'} ? Carp::longmess $msg : Carp::shortmess $msg);
    exit 0;
}

###############################################################################
# Main Program
###############################################################################
#
MAIN: {
    $SIG{__WARN__} = sub { die shift };
    $SIG{__DIE__} = \&Main::handler;

    ###############################################################################
    # AppName: (mandatory parameter)
    ###############################################################################
    #
    my $app_name = $cgi->param ('app') || die "Missing mandatory parameter 'app'!\n";
    ($app_name =~ m/^\w+$/) || die "Invalid characters in parameter 'app'\n";

    $jconfig = new Jarvis::Config ($app_name, 'etc_dir' => ($ENV{'JARVIS_ETC'} || "/opt/jarvis/etc"));

    ###############################################################################
    # Action: "status", "fetch", "update".
    ###############################################################################
    #
    # Must have an action.
    my $action = $cgi->param ('action') || die "Missing mandatory parameter 'action'!\n";
    ($action =~ m/^\w+$/) || die "Invalid characters in parameter 'action'\n";

    $jconfig->{'action'} = $action;
    my $allow_new_login = (($action eq "status") || ($action eq "fetch"));

    &Jarvis::Login::check ($jconfig, $allow_new_login);

    &Jarvis::Error::debug ($jconfig, "User Name = " . $jconfig->{'username'});
    &Jarvis::Error::debug ($jconfig, "Group List = " . $jconfig->{'group_list'});

    # Status.  I.e. are we logged in?
    if ($action eq "status") {

        my $cookie = CGI::Cookie->new (-name => $jconfig->{'sname'}, -value => $jconfig->{'sid'});
        my $return_text = &Jarvis::Status::report ($jconfig);
        print $cgi->header(-type => "text/plain", -cookie => $cookie);
        print $return_text;

    # Logout.  Clear session ID cookie, clean login parameters, then return "logged out" status.
    } elsif ($action eq "logout") {

        $jconfig->{'sid'} = '';
        my $cookie = CGI::Cookie->new (-name => $jconfig->{'sname'}, -value => $jconfig->{'sid'});
        if ($jconfig->{'logged_in'}) {
            $jconfig->{'logged_in'} = 0;
            $jconfig->{'error_string'} = "Logged out at client request.";
            $jconfig->{'username'} = '';
            $jconfig->{'group_list'} = '';
        }

        my $return_text = &Jarvis::Status::report ($jconfig);
        print $cgi->header(-type => "text/plain", -cookie => $cookie);
        print $return_text;

    # Fetch.  I.e. get some data.
    } elsif ($action eq "fetch") {

        my $cookie = CGI::Cookie->new (-name => $jconfig->{'sname'}, -value => $jconfig->{'sid'});
        my $return_text = &Jarvis::Dataset::fetch ($jconfig);
        print $cgi->header(-type => "text/plain", -cookie => $cookie);
        print $return_text;

    # Store.  I.e. alter some data.
    } elsif ($action eq "store") {

        my $cookie = CGI::Cookie->new (-name => $jconfig->{'sname'}, -value => $jconfig->{'sid'});
        my $return_text = &Jarvis::Dataset::store ($jconfig);
        print $cgi->header(-type => "text/plain", -cookie => $cookie);
        print $return_text;

    # A custom exec for this application?  We hand off entirely for this case,
    # since the MIME type may be special.  Exec::Do will add the cookie in the
    # cases where it is doing the header.  But if the exec script itself is
    # doing all the headers, then there will be no session cookie.
    #
    } elsif (&Jarvis::Exec::do ($jconfig, $action)) {
        # All is well if this returns true.  The action is treated.

    # A custom plugin for this application?  This is very similar to an Exec,
    # except that where an exec is a `<command>` system call, a Plugin is a
    # dynamically loaded module method.
    #
    } elsif (&Jarvis::Plugin::do ($jconfig, $action)) {
        # All is well if this returns true.  The action is treated.

    # It's the end of the world as we know it.
    } else {
        die "Unsupported action '" . $action . "'!\n";
    }

    ###############################################################################
    # Cleanup.
    ###############################################################################
    #
    &Jarvis::DB::Disconnect ($jconfig);
}

1;
