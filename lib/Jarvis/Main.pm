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
#       This contains the top-level "Main" body of the Jarvis processing,
#       call it either from Agent.pm (for mod_perl) or agent.pl (if not
#       using mod_perl).
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

package Jarvis::Main;

use CGI;
use File::Basename;
use Data::Dumper;

use Jarvis::Error;
use Jarvis::Config;
use Jarvis::Login;
use Jarvis::Dataset;
use Jarvis::Status;
use Jarvis::Habitat;
use Jarvis::Exec;
use Jarvis::Plugin;
use Jarvis::Hook;
use Jarvis::DB;
use Jarvis::Tracker;

###############################################################################
# Global variables.
###############################################################################
#
# Note that global variables under mod_perl require careful consideration!
#
# Specifically, you must ensure that all variables which require 
# re-initialisation for each invocation will receive it.
#

# This is our CGI object.  
# We pass it into our Jasper::Config, and also use it in our "die" error handler.
#
# It is safe because it is re-initialised in Main::do.
#
my $cgi = undef;

# This is our Jasper Config object which is passed around everywhere, and is
# used in our "die" error handler so it needs to be module wide.
#
# It is safe because it is re-initialised in Main::do.
#
my $jconfig = undef;

# This is where we might look for etc directories.
#
# It is safe because it is never modified so does not need re-initialisation.
#
my @etc = ('/etc/jarvis', '/opt/jarvis/etc');

###############################################################################
# Debugging for our old friend XML::Smart and its beloved clean errors.
###############################################################################
#
use XML::Smart; 
{
    no warnings 'redefine';
    sub XML::Smart::DESTROY {
      my $this = shift ;
      # print STDERR "In XML::Smart::DESTROY.\n";
      # print STDERR "  (object) is a " . ref ($this) . "\n";
      # print STDERR ($$this ? "  and is defined.\n" : "  but is null.\n");
      $$this && $$this->clean ;    
    }
}

###############################################################################
# Setup error handler.
###############################################################################
#
sub error_handler {
    my ($msg) = @_;

    # Truncate any thing after a null-TERM.  This is because LDAP error
    # messages sometimes put some junk in, which means that the browser
    # thinks the error is binary, and doesn't display it.
    $msg =~ s/\x00.*$//;
    $msg =~ s/\s*$/\n/;

    # Return error to client.  Note that we do not print stack trace to user, 
    # since that is a potential security weakness.
    $jconfig->{'status'} = $jconfig->{'status'} || "500 Internal Server Error"; 
    my $status = $jconfig->{'status'};
    print $cgi->header(-status => $status, -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
    print $msg;

    # Print URI to log if not done already.
    &Jarvis::Error::log ($jconfig, "processed URI = $ENV{REQUEST_URI}") unless ($jconfig->{'debug'});

    # Print to error log.  Include stack trace if debug is enabled.
    my $long_msg = &Jarvis::Error::print_message ($jconfig, 'fatal', $msg);
    print STDERR ($jconfig->{'debug'} ? Carp::longmess $long_msg : Carp::shortmess $long_msg);

    # Track this error, if we got far enough to have enough info.
    $jconfig && &Jarvis::Tracker::error ($jconfig, $status, Carp::longmess $long_msg);

    # We MUST ensure that ALL the cached database handles are removed.
    # Otherwise, under mod_perl, the next application would get OUR database handles!
    &Jarvis::DB::disconnect ($jconfig);
    
    # Perhaps we need more clean-up in here, since we may also be serving  
    # Jarvis from a perl HTTPD in some cases.  Need to keep an eye out for
    # any other resource leaks.
}

###############################################################################
# Get $jconfig singleton.  Not designed for internal use.
###############################################################################
#
sub jconfig {
    return $jconfig;
}

###############################################################################
# Main "do" method.
###############################################################################
#
sub do {
    my $options = shift;
    
    $SIG{__WARN__} = sub { die shift };
    $SIG{__DIE__} = \&Jarvis::Main::error_handler;

    # Optional mod-perl stream output variable
    my $mod_perl_io = $options && $options->{mod_perl_io};
    
    # CGI object for all sorts of things.
    $cgi = ($options && $options->{cgi}) || new CGI;

    # Environment variables.
    my $jarvis_root = $ENV {'JARVIS_ROOT'};
    foreach my $inc (@INC) {
        last if $jarvis_root;
        if (-f "$inc/Jarvis/Main.pm") {
            $jarvis_root = dirname ($inc);
        }
    }
    $jarvis_root || die "Cannot determine JARVIS_ROOT.";

    my $jarvis_etc = $ENV {'JARVIS_ETC'};
    foreach my $etc (@etc) {
        last if $jarvis_etc;
        if (-d $etc) {
            $jarvis_etc = $etc;
        }
    }
    $jarvis_etc || die "Cannot determine JARVIS_ETC.";    

    ###############################################################################
    # Determine app name (and possibly data-set).
    ###############################################################################
    #
    my $script_name = $cgi->script_name();
    my $path = $cgi->path_info() ||
        die "Missing path info.  Send $script_name/<app>[/<dataset>[/<arg1>...]] in URI!\n";

    my $method = $cgi->request_method() || 'GET';
    #
    # We don't suppport OPTIONS requests, so return a 501 Not Implemented.
    if ($method eq "OPTIONS") {
        print $cgi->header(-status => '501 Not Implemented', -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
        return;
    }

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

    # Dataset name can't be empty.  Also, it can only be normal characters 
    # with "-", and "." for directory separator.
    #
    # Note that we don't check yet for leading and trailing dot and other file 
    # security stuff.  We'll do that when we actually go to open the file, 
    # because maybe some execs/plugins might allow it, and we don't want
    # to restrict them.
    #
    # A "metaset" will allow multiple comma-separated dataset names.  This is allowed
    # only for "fetch" and only for XML or JSON formats.  There will be additional 
    # checks to follow to ensure that "," datasets are used only in specific cases.
    #
    ($dataset_name eq '') && die "All requests require $script_name/$app_name/<dataset-or-special>[/<arg1>...] in URI!\n";
    ($dataset_name =~ m|^[\w\-\.,]+$|) || die "Invalid dataset_name '$dataset_name'!\n";    

    ###############################################################################
    # Some additional parameter parsing code, because of CGI.pm oddness.
    ###############################################################################
    #
    # Explanation: In the heart of CGI.pm, there is special handling for content
    # type "application/xml" which reads the query string args from the URI
    # such as "_method=<transaction-type>" and parses them as CGI parameters.
    #
    # That code is invoked specifically only for POST "application/xml".  However
    # we really want exactly the same done for OTHER application types.  Hence
    # the following.
    #
    my $content_type = $ENV{'CONTENT_TYPE'} || 'text/plain';

    if (($method eq "POST") && ($content_type ne 'application/xml')) {
        my $query_string = '';
        if (exists $ENV{MOD_PERL}) {
            $query_string = $cgi->r->args;

        } else {
            $query_string = $ENV{'QUERY_STRING'} if defined $ENV{'QUERY_STRING'};
            $query_string ||= $ENV{'REDIRECT_QUERY_STRING'} if defined $ENV{'REDIRECT_QUERY_STRING'};
        }

        if ($query_string) {
            if ($query_string =~ /[&=;]/) {
                $cgi->parse_params($query_string);
            } else {
                $cgi->add_parameter('keywords');
                $cgi->{'keywords'} = [$cgi->parse_keywordlist($query_string)];
            }
        }
    }
    
    ###############################################################################
    # Now we can create our $jconfig at last!  Debug can start too.
    ###############################################################################

    # Create $jconfig object.  This is used everywhere in Jarvis.
    $jconfig = new Jarvis::Config ($app_name, ('etc_dir' => "$jarvis_etc", 'cgi' => $cgi, 'mod_perl_io' => $mod_perl_io ) );
    
    # Store the dataset name.
    $jconfig->{'dataset_name'} = $dataset_name;

    # Determine client's IP.
    $jconfig->{'client_ip'} = $ENV{"HTTP_X_FORWARDED_FOR"} || $ENV{"HTTP_CLIENT_IP"} || $ENV{"REMOTE_ADDR"} || '';

    # Start tracking now.  Hopefully, not too much time has passed.
    &Jarvis::Tracker::start ($jconfig);

    # Debug can now occur, since we have called Config!
    &Jarvis::Error::debug ($jconfig, "URI = $ENV{REQUEST_URI}");
    &Jarvis::Error::debug ($jconfig, "Base Path = $path");
    &Jarvis::Error::debug ($jconfig, "App Name = $app_name");
    &Jarvis::Error::debug ($jconfig, "Dataset Name = $dataset_name");

    foreach my $i (0 .. $#rest_args) {
        &Jarvis::Error::debug ($jconfig, "Rest Arg " . ($i + 1) . " = " . $rest_args[$i]);
    }

    # foreach my $env (keys %ENV) {
    #     &Jarvis::Error::debug ($jconfig, "$env = $ENV{$env}");
    # }

    # my @names = $cgi->param;
    # foreach my $name (@names) {
    #     &Jarvis::Error::debug ($jconfig, "Query Param $name = " . $cgi->param ($name));
    # }

    ###############################################################################
    # Action: "status", "habitat", "logout", "fetch", "update",  or custom
    #           action from Exec or Plugin.
    ###############################################################################
    #
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

    # Load/Start application-specific start hook(s).
    &Jarvis::Hook::start_global ($jconfig);

    # Login as required.
    &Jarvis::Login::check ($jconfig);

    &Jarvis::Error::debug ($jconfig, "User Name = '" . $jconfig->{'username'} . "'");
    &Jarvis::Error::debug ($jconfig, "Group List = '" . $jconfig->{'group_list'} . "'");
    &Jarvis::Error::debug ($jconfig, "Logged In = " . $jconfig->{'logged_in'});
    &Jarvis::Error::debug ($jconfig, "Error String = '" . $jconfig->{'error_string'} . "'");
    &Jarvis::Error::debug ($jconfig, "Method = '" . $method . "'");
    &Jarvis::Error::debug ($jconfig, "Action = '" . $action . "'");

    # What kind of dataset?
    # 's' = sql, 'i' = internal, 'p' = plugin, 'e' = exec, undef for undetermined.
    $jconfig->{'dataset_type'} = undef;

    # All special datasets start with "__".
    #
    # Note that our Plugin and Execs may expect "/appname/<something-else>" so
    # we should be careful not to trample on them.
    #
    # Note that "select" is the only permissible action on special datasets.  We
    # ignore whatever action you supplied.
    #
    if ($dataset_name =~ m/^__/) {
        my $return_text = undef;
        $jconfig->{'dataset_type'} = 'i';
        $jconfig->{'action'} = 'select';

        # Status.  I.e. are we logged in?
        if ($dataset_name eq "__status") {
            &Jarvis::Error::debug ($jconfig, "Returning status special dataset.");
            $return_text = &Jarvis::Status::report ($jconfig);

        # Habitat.  Echo the contents of the "<context>...</context>" block in our app-name.xml.
        } elsif ($dataset_name eq "__habitat") {
            &Jarvis::Error::debug ($jconfig, "Returning habitat special dataset.");
            $return_text = &Jarvis::Habitat::print ($jconfig);

        # Logout.  Clear session ID cookie, clean login parameters, then return "logged out" status.
        } elsif ($dataset_name eq "__logout") {
            &Jarvis::Error::debug ($jconfig, "Returning logout special dataset.");
            &Jarvis::Login::logout ($jconfig);
            $return_text = &Jarvis::Status::report ($jconfig);

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
        $jconfig->{'dataset_type'} = 's';

        my $return_text = &Jarvis::Dataset::fetch ($jconfig, \@rest_args);

        #
        # When providing CSV output, it is most likely going to be downloaded and
        # stored by users, or downloaded and loaded into a spreadsheet application.
        #
        # So, for CSV we suggest it as an attachment, with the filename of the dataset.
        #
        if ($jconfig->{'format'} eq "csv") {
            my $filename = $jconfig->{'return_filename'} || $jconfig->{'dataset_name'} . ".csv";
            $filename =~ s/"/\\"/g;
            print $cgi->header(
                -type => 'text/csv; charset=UTF-8; name="' . $filename . '"',
                'Content-Disposition' => 'attachment; filename="' . $filename . '"',
                -cookie => $jconfig->{'cookie'},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
            
        } elsif ($jconfig->{'format'} eq "xlsx") {
            my $filename = $jconfig->{'return_filename'} || $jconfig->{'dataset_name'} . ".xlsx";
            $filename =~ s/"/\\"/g;
            print $cgi->header(
                -type => 'application/vnd.ms-excel; name="' . $filename . '"',
                'Content-Disposition' => 'attachment; filename="' . $filename . '"',
                -cookie => $jconfig->{'cookie'},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
            
        } else {
            print $cgi->header(
                -type => "text/plain; charset=UTF-8",
                -cookie => $jconfig->{'cookie'},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
        }
        print $return_text;

    # Modify a regular dataset.
    } elsif (($action eq "insert") || ($action eq "update") || ($action eq "delete") || ($action eq "mixed")) {

        # Meta-sets are for FETCH only, not STORE.
        ($dataset_name =~ m/,/) && die "Comma-Separated dataset '$dataset_name' not permitted for action '$action'\n";

        $jconfig->{'dataset_type'} = 's';
        my $return_text = &Jarvis::Dataset::store ($jconfig, \@rest_args);

        print $cgi->header(-type => "text/plain; charset=UTF-8", -cookie => $jconfig->{'cookie'});
        print $return_text;

    # It's the end of the world as we know it.
    } else {
        print $cgi->header(-status => '501 Not Implemented', -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
        print "The $method method (action $action) is not recognised by Jarvis.";
    }

    ###############################################################################
    # Cleanup.
    ###############################################################################

    # Invoke application-specific finish hook(s).
    &Jarvis::Hook::finish ($jconfig);
    # Track the request end.
    &Jarvis::Tracker::finish ($jconfig, \@rest_args);

    # We MUST ensure that ALL the cached database handles are removed.
    # Otherwise, under mod_perl, the next application would get OUR database handles!
    #
    # Note that deep in the internals of mod_perl, the underlying handle may be 
    # cached for potential re-use by DBI.  But that will ensure that the password
    # and other information matches before allowing it.
    &Jarvis::DB::disconnect ($jconfig);
}

1;
