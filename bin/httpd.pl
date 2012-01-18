#!/usr/bin/perl
###############################################################################
# Description:
#       Mini Web-Server to allow applications to use Jarvis as a complete
#       standalone server when they do not wish to install Apache.
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

package Jarvis::WebServer;

use base qw (HTTP::Server::Simple::CGI);

use Carp;
use CGI; 
use Getopt::Long;
use Pod::Usage;
use Cwd qw (abs_path);
use Net::Server::Fork;
use MIME::Types;
use Time::HiRes qw (gettimeofday tv_interval);

use lib "../lib";

use Jarvis::Main;
use Jarvis::Error;

###############################################################################
# Command line and global variables.
###############################################################################
#

# NOTE: These are temporary.  I think we should also support an XML file.
# 
# Also, we probably want to support aliaii as well.
#

my $port = 8448;
my $host = "0.0.0.0";
my $agent_prefix = "/jarvis-agent/";
my $root_dir = undef;
my $access_log = undef;
my $error_log = undef;
my $help = 0;
my $man = 0;

# Get comand line settings.
#
# Please remember to update the POD at the bottom of this file if you add
# new command line options.
#
&Getopt::Long::GetOptions (
    "agent-prefix=s" => \$agent_prefix,
    "root-dir=s" => \$root_dir,
    "port=i" => \$port,
    "host=s" => \$host,
    "access-log=s" => \$access_log,
    "error-log=s" => \$error_log,
    'help|?' => \$help,
    'man' => \$man
) || pod2usage(2);

# Help and Manpage options.
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Redirect stderr if requested.
if ($error_log) {
    open STDERR, ">>$error_log" || die "Cannot redirect STDERR: $!\n";
}

# Sanity check.
if ($root_dir) {
    (-d $root_dir) || die "The supplied root_dir is not a directory."; 
    $root_dir = abs_path ($root_dir) . "/";
    print STDERR "Using '$root_dir' as htdocs root directory.\n";
}

my $mime_types = MIME::Types->new;

###############################################################################
# Utility functions.
###############################################################################
#
sub epoch_to_gmt_822 {
    my ($epoch) = @_;

    my @days = ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun');
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

    my @g = gmtime ($epoch);
    return sprintf "%s, %d %s %04d %02d:%02d:%02d GMT", $days[$g[6]], $g[3], $months[$g[4]], 1900 + $g[5], $g[2], $g[1], $g[0];
}

# Write to the access log perhaps?
sub log_access {
    my ($cgi, $start, $code, $resource) = @_;

    if ($access_log) {
        open (my $alf, ">>$access_log") || die "Cannot open access log '$access_log': $!";

        my $elapsed = int (tv_interval ( $start, [gettimeofday]) * 1000);
        my $method = $cgi->request_method ();
        
        my $line = sprintf "%d.%03d %s %s %s\n", $$start[0], ($$start[1] / 1000), $method, $elapsed, $resource;      
        print $alf $line;
        close ($alf);
    }
}

###############################################################################
# Main Handlers
###############################################################################
#
sub net_server {
    return 'Net::Server::Fork';
}

sub handle_request {
    my ($self, $cgi) = @_;

    # We need non-parsed headers.  Normally we would rely on Apache to parse
    # headers.  But we have no Apache in this case.  We're on our own.    
    $CGI::NPH = 1;
    
    # What URL path did they request? 
    my $path = $cgi->path_info ();

    # When did the request start?    
    my $start = [gettimeofday];
    
    # These are Jarvis agent requests.  Hand them over.
    if ($path =~ m/^$agent_prefix(.*)$/) {
        
        # Remove the leading prefix from the path info.
        $cgi->path_info ($1);
        $cgi->script_name ($agent_prefix);

        # Now ask Jarvis to do its usual stuff.
        eval {
            &Jarvis::Main::do ({cgi => $cgi});
            
            my $jconfig = &Jarvis::Main::jconfig ();
            my $status = ($jconfig && $jconfig->{'status'}) || "200";
            $status =~ s/ .*//;  
            &log_access ($cgi, $start, $status, "jarvis:" . $cgi->path_info);         
        } 

    # 
    # TODO: Support alias paths (checked before htdocs).
    #

        
    # These are static document requests within htdocs.
    } elsif ($root_dir) {
        my $file_path = $path;
        $file_path =~ s|^/||;
        $file_path = $root_dir . $file_path;
        $file_path = abs_path ($file_path) || '';
        if (! $file_path) {
            print $cgi->header(-status => "404 Not Found", -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
            print "The path '$path' resolves to a directory '$file_path' which does not exist on this server.";
            &log_access ($cgi, $start, 404, "file:$file_path"); 
            return;
        }
        if (($file_path !~ m/^$root_dir/) && ($file_path . "/" ne $root_dir)) {
            print $cgi->header(-status => "404 Not Found", -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
            print "The path '$file_path' resolves to a directory '$file_path' which is not within the document root directory.";
            &log_access ($cgi, $start, 404, "file:$file_path"); 
            return;
        }
        if (-d $file_path) {
            if (-f "$file_path/index.html") {
                $file_path .= "/index.html";
                
            } else {            
                print $cgi->header(-status => "404 Not Found", -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
                print "The path '$path' resolves to a directory '$file_path'.  Directory browsing is not supported.";
                &log_access ($cgi, $start, 404, "file:$file_path"); 
                return;
            }
        }
        if (! -f $file_path) {
            print $cgi->header(-status => "404 Not Found", -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
            print "The path '$path' resolves to a file '$file_path' which does not exist.";
            &log_access ($cgi, $start, 404, "file:$file_path"); 
            return;
        }
        
        # Right, now we know the request is for a valid file.  Let's return it!
        # binmode STDIN,  ':raw';
        # binmode STDOUT, ':raw';   
        my $fh = undef;
        if (! open $fh, $file_path) {
            print $cgi->header(-status => "403 Forbidden", -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
            print "The path '$path' resolves to a file which cannot be accessed.";
            &log_access ($cgi, $start, 403, "file:$file_path"); 
            return;
        }

        # Get the MIME type.        
        my $filename_type = $mime_types->mimeTypeOf ($file_path);
        my $mime_type = $filename_type ? $filename_type->type : 'text/plain';
        
        print STDERR "MIME Type for '$file_path' is '$mime_type'\n";
                
        # Get the file stats.
        my @stat = stat ($file_path);
        if (! @stat) {
            print $cgi->header(-status => "403 Forbidden", -type => "text/plain", 'Content-Disposition' => "inline; filename=error.txt");
            print "The path '$path' resolves to a file which cannot be processed.";
            &log_access ($cgi, $start, 403, "file:$file_path"); 
            return;
        }
        my $file_bytes = $stat[7];
        my $file_mtime = $stat[9];
        
        # Return the entire file.
        my $buff;
        print $cgi->header(-status => "200 OK", -type => $mime_type, 'Content-Length' => $file_bytes, 'Last-Modified' => &epoch_to_gmt_822 ($file_mtime));
        
        binmode ($fh);
        while (read ($fh, $buff, 8 * 2**10)) {
            print STDOUT $buff;
        }        
        close ($fh);

        # Log and we're done.        
        &log_access ($cgi, $start, 200, "file:$file_path"); 
    }
}

# Prepare the Server.
my $server = Jarvis::WebServer->new () || die "Cannot start HTTP server: $!";
$server->port ($port);
$server->run (host => $host);

# We should never get here, unless we failed to run.  In which case maybe there
# is useful info in the error log.
if ($error_log) {
    print "HTTP server could not run.  Check the error log for more information.\n";
    print "  $error_log\n"; 
}

1;

 __END__

=head1 NAME

httpd - Standalone Jarvis HTTPD server, for when Apache or IIS aren't wanted.

=head1 SYNOPSIS

perl httpd.pl [options]

Options:
  --agent-prefix    prefix
  --root-dir        directory
  --port            number
  --host            address
  --access-log      file
  --error-log       file
  --help            (brief help message)
  --man             (full documentation)

=head1 OPTIONS

=over 8

=item B<--agent-prefix>

This prefix at the start of request URLs indicates that the remainder of the
request should be passed to Jarvis for processing.  The default prefix is
"/jarvis-agent/".

=item B<--root-dir>

This specifies the root directory from which static files should be served 
in the case where the requested URL does not match the agent prefix.  This 
parameter is optional and has no default.  If no root directory is specified,
then static documents will not be served.

=item B<--port>

This specifes an alternate listening port number.  The default is "8448".

=item B<--host>

This specifies a default listening host address.  The default is "0.0.0.0".

=item B<--access-log>

This file is the name of the access log.  One line will be appended to this
file for each incoming request.  The format of the access log file is:  

  <epoch> <method> <elapsed-ms> <request-type>:<path>

e.g.

  1326924314.984 GET 1474 jarvis:/exoviz/mdx.pnl_summary
  
This parameter has no default.  If not specified, then access logs will not
be written.

=item B<--error-log>

This file specifies an alternate destination for redirecting STDERR output.
By default, error and debug (including Jarvis debug) is written to STDERR.

=item B<--help>

Print a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 DESCRIPTION

B<httpd.pl> is a standalone HTTP web-server, designed to be run on simple 
installations where Jarvis functionality is required, along with very basic
serving of static documents.  In such cases, the installation overhead 
associated with Apache, IIS or other full-featured web servers is not required.

It does not detach from the command line.

=cut

