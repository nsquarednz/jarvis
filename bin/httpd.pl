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

my $port = 8080;
my $agent_prefix = "/jarvis-agent/";
my $root_dir = "/home/jcouper/dev/exoviz/htdocs/";
my $access_log = undef;

# Get comand line settings.
&Getopt::Long::GetOptions (
    "agent-prefix=s" => \$agent_prefix,
    "root-dir=s" => \$root_dir,
    "port=i" => \$port,
    "access_log=s" => \$access_log
)
|| die "Cannot parse command line options.";

# Sanity check.
if ($root_dir) {
    (-d $root_dir) || die "The supplied root_dir is not a directory."; 
    $root_dir = abs_path ($root_dir) . "/";
    print STDERR "Using '$root_dir' as htdocs root directory.\n";
}


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
        # die $line;
        print $alf $line;
        close ($alf);
    }
}

###############################################################################
# Main Handlers
###############################################################################
#
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
    } else {
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
        my $mime_types = MIME::Types->new;
        my $filename_type = $mime_types->mimeTypeOf ($file_path);
        my $mime_type = $filename_type ? $filename_type->type : 'text/plain';
                
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

my $net_server = Net::Server::Fork->new ();;

my $server = Jarvis::WebServer->new () || die "Cannot start HTTP server: $!";
$server->net_server ($net_server);
$server->port ($port);
$server->run ();

1;
