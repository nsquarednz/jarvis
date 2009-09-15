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
use Jarvis::Habitat;
use Jarvis::Exec;
use Jarvis::Plugin;
use Jarvis::DB;

package Main;

# Default jarvis etc.
my $default_jarvis_etc = "/opt/jarvis/etc";

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
    $msg =~ s/\s*$/\n/;

    # Return error.  Note that we do not print stack trace to user, since
    # that is a potential security weakness.
    my $status = $jconfig->{'status'} || "500 Internal Server Error";
    print $cgi->header(-status => $status, -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
    print $msg;

    # Print to error log.  Include stack trace if debug is enabled.
    my $long_msg = &Jarvis::Error::print_message ($jconfig, 'fatal', $msg);
    print STDERR ($jconfig->{'debug'} ? Carp::longmess $long_msg : Carp::shortmess $long_msg);

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
    # Determine app name (and possibly data-set).
    ###############################################################################
    #

    my $script_name = $cgi->script_name();
    my $path = $cgi->path_info() ||
        die "Missing path info.  Send $script_name/<app>[/<dataset>[/<arg1>...]] in URI!\n";

    # Clean up our path to remove & args, # names, and finally leading and trailing
    # spaces and slashes.
    #
    $path =~ s|(?<!\\)&.*$||;
    $path =~ s|(?<!\\)#.*$||;
    $path =~ s|^\s*/||;
    $path =~ s|/\s*$||;

    # Parse our app-name, optional dataset-name and REST args.  Note that path is no longer
    # URL-encoded by the time it gets to us.  Setting AllowEncodedSlashes doesn't help us
    # get slashes through to this point.  So we do a special case and allow \/ to escape
    # a slash through to our REST args.
    #
    my ($app_name, $dataset_name, @rest_args) = split ( m|(?<!\\)/|, $path);
    @rest_args = map { s|\\/|/|g; $_ } @rest_args;

    $app_name || ($app_name = '');
    $dataset_name || ($dataset_name = '');

    # Check app_name is OK.
    $app_name || die "Missing app name.  Send $script_name/<app>[/<dataset>[/<arg1>...]] in URI!\n";
    $app_name =~ m|^[\w\-]+$| || die "Invalid app_name '$app_name'!\n";

    # Dataset name can't be empty, and can only be normal characters with "-", and "."
    # for directory separator.  Note that we don't check yet for leading and trailing
    # dot and other file security stuff.  We'll do that when we actually go to open
    # the file, because maybe some execs/plugins might allow it, and we don't want
    # to restrict them.
    #
    ($dataset_name eq '') || ($dataset_name =~ m|^[\w\-\.]+$|) || die "Invalid dataset_name '$dataset_name'!\n";

    $jconfig = new Jarvis::Config ($app_name, 'etc_dir' => ($ENV{'JARVIS_ETC'} || $default_jarvis_etc));
    $dataset_name && ($jconfig->{'dataset_name'} = $dataset_name);

    # Debug can now occur, since we have called Config!
    &Jarvis::Error::debug ($jconfig, "Base Path = $path");
    &Jarvis::Error::debug ($jconfig, "App Name = $app_name");
    &Jarvis::Error::debug ($jconfig, "Dataset Name = $dataset_name");

    foreach my $i (0 .. $#rest_args) {
        &Jarvis::Error::debug ($jconfig, "Rest Arg " . ($i + 1) . " = " . $rest_args[$i]);
    }

    # foreach my $env (keys %ENV) {
    #     &Jarvis::Error::debug ($jconfig, "$env = $ENV{$env}");
    # }

    ###############################################################################
    # Action: "status", "habitat", "logout", "fetch", "update",  or custom
    #           action from Exec or Plugin.
    ###############################################################################
    #
    my $method = $cgi->request_method() || '';

    my $method_param = $jconfig->{'method_param'};
    if ($method_param) {
        my $new_method = $cgi->param($method_param);
        if ($new_method) {
            &Jarvis::Error::debug ($jconfig, "Using Method '$new_method' instead of '" . $method ."'");
            $method = $new_method;
        }
    }

    my $action = lc ($method) || die "Missing request method!\n";
    ($action =~ m/^\w+$/) || die "Invalid characters in parameter 'action'\n";

    # Now canonicalise our action.
    if ($action eq 'get') { $action = 'select' };
    if ($action eq 'fetch') { $action = 'select' };
    if ($action eq 'post') { $action = 'insert' };
    if ($action eq 'create') { $action = 'insert' };
    if ($action eq 'put') { $action = 'update' };

    $jconfig->{'action'} = $action;

    &Jarvis::Login::check ($jconfig);

    &Jarvis::Error::debug ($jconfig, "User Name = '" . $jconfig->{'username'} . "'");
    &Jarvis::Error::debug ($jconfig, "Group List = '" . $jconfig->{'group_list'} . "'");
    &Jarvis::Error::debug ($jconfig, "Logged In = " . $jconfig->{'logged_in'});
    &Jarvis::Error::debug ($jconfig, "Error String = '" . $jconfig->{'error_string'} . "'");
    &Jarvis::Error::debug ($jconfig, "Method = '" . $method . "'");
    &Jarvis::Error::debug ($jconfig, "Action = '" . $action . "'");

    # Check we have a dataset.
    $dataset_name || die "All requests requires $script_name/$app_name/<dataset-or-special>[/<arg1>...] in URI!\n";

    # All special datasets start with "__".
    #
    # Note that our Plugin and Execs may expect "/appname/<something-else>" so
    # we should be careful not to trample on them.  We only interpret these
    # special datasets for the four main CRUD actions.
    #
    if ($dataset_name =~ m/^__/) {
        my $return_text = undef;

        # Status.  I.e. are we logged in?
        if ($dataset_name eq "__status") {
            &Jarvis::Error::debug ($jconfig, "Returning status special dataset.");
            $return_text = &Jarvis::Status::report ($jconfig, \@rest_args);

        # Habitat.  Echo the contents of the "<context>...</context>" block in our app-name.xml.
        } elsif ($dataset_name eq "__habitat") {
            &Jarvis::Error::debug ($jconfig, "Returning habitat special dataset.");
            $return_text = &Jarvis::Habitat::print ($jconfig, \@rest_args);

        # Logout.  Clear session ID cookie, clean login parameters, then return "logged out" status.
        } elsif ($dataset_name eq "__logout") {
            &Jarvis::Error::debug ($jconfig, "Returning logout special dataset.");
            &Jarvis::Login::logout ($jconfig);
            $return_text = &Jarvis::Status::report ($jconfig, \@rest_args);

        # Starts with __ so must be special, but we don't know it.
        } else {
            die "Unknown special dataset '$dataset_name'!\n";
        }

        print $cgi->header(-type => "text/plain; charset=UTF-8", -cookie => $jconfig->{'cookie'}, 'Cache-Control' => 'no-store, no-cache, must-revalidate');
        print $return_text;

    # A custom exec for this application?  We hand off entirely for this case,
    # since the MIME type may be special.  Exec::Do will add the cookie in the
    # cases where it is doing the header.  But if the exec script itself is
    # doing all the headers, then there will be no session cookie.
    #
    } elsif (&Jarvis::Exec::do ($jconfig, $dataset_name, \@rest_args)) {
        # All is well if this returns true.  The action is treated.

    # A custom plugin for this application?  This is very similar to an Exec,
    # except that where an exec is a `<command>` system call, a Plugin is a
    # dynamically loaded module method.
    #
    } elsif (&Jarvis::Plugin::do ($jconfig, $dataset_name, \@rest_args)) {
        # All is well if this returns true.  The action is treated.

    # Fetch a regular dataset.
    } elsif ($action eq "select") {

        my $return_text = &Jarvis::Dataset::fetch ($jconfig, \@rest_args);

        print $cgi->header(-type => "text/plain; charset=UTF-8", -cookie => $jconfig->{'cookie'}, 'Cache-Control' => 'no-store, no-cache, must-revalidate');
        print $return_text;

    # Modify a regular dataset.
    } elsif (($action eq "insert") || ($action eq "update") || ($action eq "delete") || ($action eq "mixed")) {

        my $return_text = &Jarvis::Dataset::store ($jconfig, \@rest_args);

        print $cgi->header(-type => "text/plain; charset=UTF-8", -cookie => $jconfig->{'cookie'});
        print $return_text;

    # It's the end of the world as we know it.
    } else {
        die "Unsupported action '" . $action . "' ($method)!\n";
    }

    ###############################################################################
    # Cleanup.
    ###############################################################################
    #
    &Jarvis::DB::Disconnect ($jconfig);
}

1;
