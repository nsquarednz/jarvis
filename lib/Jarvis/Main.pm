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
use Jarvis::Route;

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

# Version 6.0.0.
$Jarvis::Main::JARVIS_VERSION = 601;

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
# Generate a random UUID. Avoid any reliance on 3rd party UUID generator
# perl modules due to the difficulty in yum/apt installation procedures on
# most target systems.
#
# This approach here is a UUID generated based on random numbers - and is based
# off of Perl's UUID::Tiny module.
###############################################################################
#
sub generate_uuid {
    my $uuid = '';
    for (1 .. 4) {
        my $top = int(rand(65536)) % 65536;
        my $bottom = int(rand(65536)) % 65536;
        $uuid .= pack 'I', (($top << 16) | $bottom);
    }
    substr $uuid, 6, 1, chr(ord(substr($uuid, 6, 1)) & 0x0f);
    substr $uuid, 8, 1, chr(ord(substr $uuid, 8, 1) & 0x3f | 0x80);
    return join '-', map { unpack 'H*', $_ } map { substr $uuid, 0, $_, '' } ( 4, 2, 2, 2, 6 );
}

###############################################################################
# Setup error handler.
###############################################################################
#
sub error_handler {
    my ($msg) = @_;

    # Are we parsing ($^S undef) or executing ($^S == 1) an eval?
    #
    # If this is an "eval" within a Jarvis plugin, then we don't want to fire
    # this "die" handler and shut down the whole process, that's a massive
    # over-reaction.
    #
    # The problem arises when running under mod_perl.  The mod_perl wrapper
    # runs everything inside its own "eval", which we detect, and confuse
    # with a Jarvis plugin "eval". 
    #
    if ((! defined $^S) or ($^S == 1)) {

    	# Go up the caller stack and see if we find an "(eval)" before we hit "Jarvis::Main::do".
     	my $frames = 0;
    	while (1) {
    	    my @frame = caller ($frames);
    	    if (! scalar (@frame)) {
                die "Cannot find '(eval)' frame in call stack.";
    	    }
    	    my $subroutine = $frame[3];

    	    # If we hit "(eval)" before Jarvis::Main::do, then that means this is a user-eval.
    	    # We don't want to die at all in this case!  Just return and let the user's "eval" 
    	    # post-processing run and deal with things.
    	    if ($subroutine eq '(eval)') {
                return;

    	    # Otherwise if we got to "Jarvis::Main::do" without hitting a user "(eval)" then
    	    # this means that something really did call a "die", and we really do want to
    	    # invoke this handler and return a message back to the client.
    	    } elsif ($subroutine eq 'Jarvis::Main::do') {
                last;
    	    }
    	    $frames++;
    	}
    }

    # Truncate any thing after a null-TERM.  This is because LDAP error
    # messages sometimes put some junk in, which means that the browser
    # thinks the error is binary, and doesn't display it.
    $msg =~ s/\x00.*$//;
    $msg =~ s/\s*$/\n/;

    # Return error to client.  Note that we do not print stack trace to user, 
    # since that is a potential security weakness.
    $jconfig->{status} = $jconfig->{status} || "500 Internal Server Error"; 
    my $status = $jconfig->{status};
    print $cgi->header(-status => $status, -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
    if ($status =~ /^500/) {
        print &Jarvis::Error::print_message ($jconfig, $jconfig->{error_response_format} || "[%T][%R] %M", 'fatal', $msg);
    } else {
        print $msg;
    }

    # Print to error log.  Include stack trace if debug is enabled.
    my $long_msg = &Jarvis::Error::print_log_message ($jconfig, 'fatal', $msg);

    # Print URI to log if not done already.
    if (! $jconfig->{debug}) {
        $long_msg = $long_msg . "        URI = $ENV{REQUEST_URI}";
    }

    if ($status =~ /^500/) {
        print STDERR ($jconfig->{debug} ? Carp::longmess $long_msg : Carp::shortmess $long_msg);
    }

    # We MUST ensure that ALL the cached database handles are removed.
    # Otherwise, under mod_perl, the next application would get OUR database handles!
    &Jarvis::DB::disconnect ($jconfig, undef, undef, 1);
    
    # Under mod_perl this will be ModPerl::Util::exit (), which won't really end the process.
    # Under non-mod_perl, this will really exit the process.
    exit ();
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
#
# This method is called by either:
#	Main::Agent (mod_perl case) or 
#	agent.pl (non-mod_perl case)
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
    my $jarvis_root = $ENV {JARVIS_ROOT};
    foreach my $inc (@INC) {
        last if $jarvis_root;
        if (-f "$inc/Jarvis/Main.pm") {
            $jarvis_root = dirname ($inc);
        }
    }
    $jarvis_root || die "Cannot determine JARVIS_ROOT.";

    my $jarvis_etc = $ENV {JARVIS_ETC};
    foreach my $etc (@etc) {
        last if $jarvis_etc;
        if (-d $etc) {
            $jarvis_etc = $etc;
        }
    }
    $jarvis_etc || die "Cannot determine JARVIS_ETC.";    

    ###############################################################################
    # Check basic HTML parameters.
    ###############################################################################
    #
    my $script_name = $cgi->script_name();
    my $path = $cgi->path_info() ||
        die "Missing path info.  Send $script_name/<app-name>/<arg0>[/<arg1>...] in URI!\n";

    my $method = $cgi->request_method() || 'GET';
    #
    # We don't suppport OPTIONS requests, so return a 501 Not Implemented.
    if ($method eq "OPTIONS") {
        print $cgi->header(-status => '501 Not Implemented', -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
        return;
    }

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
    my $content_type = $ENV{CONTENT_TYPE} || 'text/plain';

    if (($method eq "POST") && ($content_type ne 'application/xml')) {
        my $query_string = '';
        if (exists $ENV{MOD_PERL}) {
            $query_string = $cgi->r->args;

        } else {
            $query_string = $ENV{QUERY_STRING} if defined $ENV{QUERY_STRING};
            $query_string ||= $ENV{REDIRECT_QUERY_STRING} if defined $ENV{REDIRECT_QUERY_STRING};
        }

        if ($query_string) {
            if ($query_string =~ /[&=;]/) {
                $cgi->parse_params($query_string);
            } else {
                $cgi->add_parameter('keywords');
                $cgi->{keywords} = [$cgi->parse_keywordlist($query_string)];
            }
        }
    }
    
    ###############################################################################
    # Get our app name and read our $jconfig at last!  Debug can start too.
    ###############################################################################

    # Clean up our path to remove & args, # names.  
    $path =~ s|(?<!\\)&.*$||;
    $path =~ s|(?<!\\)#.*$||;

    # Remove leading slash to expose the application name.
    $path =~ s|^/||;

    # Parse our app-name and REST args.  Note that path is no longer
    # URL-encoded by the time it gets to us.  Setting AllowEncodedSlashes doesn't help us
    # get slashes through to this point.  So we do a special case and allow \/ to escape
    # a slash through to our REST args.
    #
    my ($app_name, @path_parts) = split ( m|(?<!\\)/|, $path, -1);
    @path_parts = map { s|\\/|/|g; $_ } @path_parts;

    if (! $app_name) {
        die "Missing app-name.  Send $script_name/<app-name>/<arg0>[/<arg1>...] in URI!\n";
    }
    $app_name =~ m|^[\w\-]+$| || die "Invalid app_name '$app_name'!\n";

    # Create $jconfig object.  This is used everywhere in Jarvis.
    $jconfig = new Jarvis::Config ($app_name, ('etc_dir' => "$jarvis_etc", 'cgi' => $cgi, 'mod_perl_io' => $mod_perl_io ) );

    # Determine client's IP.
    $jconfig->{client_ip} = $ENV{"HTTP_X_FORWARDED_FOR"} || $ENV{"HTTP_CLIENT_IP"} || $ENV{"REMOTE_ADDR"} || '';

    # Determine a unique request ID for this request. Useful for tracing and auditing.
    # This will later get expanded to incorporate the session ID, if we have one.
    $jconfig->{request_id} = generate_uuid();

    # Debug can now occur, since we have called Config!
    &Jarvis::Error::debug ($jconfig, "URI = $ENV{REQUEST_URI}");
    &Jarvis::Error::debug ($jconfig, "Base Path = '$path'.");
    &Jarvis::Error::debug ($jconfig, "App Name = '$app_name'.");
    foreach my $i (0 .. $#path_parts) {
        &Jarvis::Error::debug ($jconfig, "Parsed Path Part $i => '%s'.", $path_parts[$i]);
    }

    ###############################################################################
    # Now we can start with the real action.  Start parsing
    ###############################################################################

    # Now parse the rest of the args and apply our router.  This gives us dataset name too.
    my ($dataset_name, $user_args, $presentation) = &Jarvis::Route::find ($jconfig, \@path_parts);

    # Store this for debugging.
    $jconfig->{dataset_name} = $dataset_name;
    &Jarvis::Error::debug ($jconfig, "Dataset Name = '%s'.", $dataset_name);
    &Jarvis::Error::debug ($jconfig, "Presentation = '%s'.", $presentation);

    # Store the presentation for later encoding.
    $jconfig->{presentation} = $presentation;

    # Show our rest args.
    foreach my $key (sort (keys %$user_args)) {
        &Jarvis::Error::debug ($jconfig, "Rest Arg: '$key' => '%s'.", $$user_args{$key});
    }

    # Merge in the CGI vars.  Do NOT override REST args.
    my $cgi_params = $jconfig->{cgi}->Vars;
    foreach my $name (keys %$cgi_params) {
        next if ($name !~ m/^_?[a-z][a-z0-9_\-]*$/i);
        next if ($name eq 'POSTDATA');
        next if (defined $user_args->{$name});

        if (length ($cgi_params->{$name}) > 256) {
            &Jarvis::Error::debug ($jconfig, "CGI Param: '$name' => (%d bytes).", length ($cgi_params->{$name}));

        } else {
            &Jarvis::Error::debug ($jconfig, "CGI Param: '$name' => '%s'.", $cgi_params->{$name});
        }
        $user_args->{$name} = $cgi_params->{$name};
    }

    # Dataset name can't be empty.  Also, it can only be normal characters 
    # with "-", and "." for directory separator.
    #
    # Note that we don't check yet for leading and trailing dot and other file 
    # security stuff.  We'll do that when we actually go to open the file, 
    # because maybe some execs/plugins might allow it, and we don't want
    # to restrict them.
    #
    if ((! defined $dataset_name) || ($dataset_name eq '')) {
        die "All requests require $script_name/$app_name/<dataset-or-special>[/<arg1>...] in URI!\n";
    }
    ($dataset_name =~ m|^[\w\-\.]+$|) || die "Invalid dataset_name '$dataset_name'!\n";    

    ###############################################################################
    # Action: "status", "habitat", "logout", "fetch", "update",  or custom
    #           action from Exec or Plugin.
    ###############################################################################
    #
    my $method_param = $jconfig->{method_param};
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

    $jconfig->{action} = $action;

    # Load/Start application-specific start hook(s).
    &Jarvis::Hook::load_global ($jconfig);

    # Login as required.
    &Jarvis::Login::check ($jconfig);

    # Now we have some login data - lets expand our request UUID to be a unique session/request UUID
    &Jarvis::Error::debug ($jconfig, "User Name = '" . $jconfig->{username} . "'");
    &Jarvis::Error::debug ($jconfig, "Group List = '" . $jconfig->{group_list} . "'");
    &Jarvis::Error::debug ($jconfig, "Logged In = " . $jconfig->{logged_in});
    &Jarvis::Error::debug ($jconfig, "Request ID = '" . $jconfig->{request_id} . "'.");
    &Jarvis::Error::debug ($jconfig, "Error String = '" . $jconfig->{error_string} . "'");
    &Jarvis::Error::debug ($jconfig, "Method = '" . $method . "'");
    &Jarvis::Error::debug ($jconfig, "Action = '" . $action . "'");

    # What kind of dataset?  Used by the tracker only.
    # 's' = sql, 'i' = internal, 'p' = plugin, 'e' = exec, undef for undetermined.
    $jconfig->{dataset_type} = undef;

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
        $jconfig->{dataset_type} = 'i';
        $jconfig->{action} = 'select';

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

        print $cgi->header(-type => "text/plain; charset=UTF-8", -cookie => $jconfig->{cookie}, 'Cache-Control' => 'no-store, no-cache, must-revalidate');
        print $return_text;

    # A custom exec for this application?  We hand off entirely for this case,
    # since the MIME type may be special.  Exec::Do will add the cookie in the
    # cases where it is doing the header.  But if the exec script itself is
    # doing all the headers, then there will be no session cookie.
    #
    } elsif (&Jarvis::Exec::do ($jconfig, $dataset_name, $user_args)) {
        # All is well if this returns true.  The action is treated.
        $jconfig->{dataset_type} = 'e';

    # A custom plugin for this application?  This is very similar to an Exec,
    # except that where an exec is a `<command>` system call, a Plugin is a
    # dynamically loaded module method.
    #
    } elsif (&Jarvis::Plugin::do ($jconfig, $dataset_name, $user_args)) {
        # All is well if this returns true.  The action is treated.
        $jconfig->{dataset_type} = 'p';

    # Fetch a regular dataset.
    } elsif ($action eq "select") {
        $jconfig->{dataset_type} = 's';

        my $return_text = &Jarvis::Dataset::fetch ($jconfig, $dataset_name, $user_args);

        #
        # When providing CSV output, it is most likely going to be downloaded and
        # stored by users, or downloaded and loaded into a spreadsheet application.
        #
        # So, for CSV we suggest it as an attachment, with the filename of the dataset.
        #
        if ($jconfig->{format} eq "csv") {
            my $filename = $jconfig->{return_filename} || $dataset_name . ".csv";
            $filename =~ s/"/\\"/g;
            print $cgi->header(
                -type => 'text/csv; charset=UTF-8; name="' . $filename . '"',
                'Content-Disposition' => 'attachment; filename="' . $filename . '"',
                -cookie => $jconfig->{cookie},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
            
        } elsif ($jconfig->{format} eq "xlsx") {
            my $filename = $jconfig->{return_filename} || $dataset_name . ".xlsx";
            $filename =~ s/"/\\"/g;
            print $cgi->header(
                -type => 'application/vnd.ms-excel; name="' . $filename . '"',
                'Content-Disposition' => 'attachment; filename="' . $filename . '"',
                -cookie => $jconfig->{cookie},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
            
        } else {
            print $cgi->header(
                -type => "text/plain; charset=UTF-8",
                -cookie => $jconfig->{cookie},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
        }
        print $return_text;

    # Modify a regular dataset.
    } elsif (($action eq "insert") || ($action eq "update") || ($action eq "delete") || ($action eq "mixed")) {

        $jconfig->{dataset_type} = 's';
        my $return_text = &Jarvis::Dataset::store ($jconfig, $dataset_name, $user_args);

        print $cgi->header(-type => "text/plain; charset=UTF-8", -cookie => $jconfig->{cookie});
        print $return_text;

    # It's the end of the world as we know it.
    } else {
        print $cgi->header(-status => '501 Not Implemented', -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
        print "The $method method (action $action) is not recognised by Jarvis.";
    }

    ###############################################################################
    # Cleanup.
    ###############################################################################

    # Unload our global hooks.  This will call ::finish on them.
    &Jarvis::Hook::unload_global ($jconfig);

    # We MUST ensure that ALL the cached database handles are removed.
    # Otherwise, under mod_perl, the next application would get OUR database handles!
    #
    # Note that deep in the internals of mod_perl, the underlying handle may be 
    # cached for potential re-use by DBI.  But that will ensure that the password
    # and other information matches before allowing it.
    &Jarvis::DB::disconnect ($jconfig);
}

1;
