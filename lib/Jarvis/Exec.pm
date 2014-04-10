###############################################################################
# Description:  Performs a custom <exec> dataset defined in the <app_name>.xml
#               file for this application.  A good example of this would be
#               an exec dataset which handed off to a report script like
#               javis.
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

package Jarvis::Exec;

use File::Temp;
use File::Basename;
use MIME::Types;
use Data::Dumper;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

################################################################################
# Runs a command.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               xml
#               cgi
#
#       $dataset_name - Name of the special "exec" dataset we are requested to perform.
#
#       $rest_args - A ref to our hash of REST args (numbered and named)
#
# Returns:
#       0 if the dataset is not a known "exec" dataset
#       1 if the dataset is known and successful
#       die on error attempting to perform the dataset
################################################################################
#
sub do {
    my ($jconfig, $dataset, $rest_args) = @_;

    ###############################################################################
    # See if we have any extra "exec" dataset for this application.
    ###############################################################################
    #
    my $allowed_groups = undef;         # Access groups permitted, or "*" or "**"
    my $command = undef;                # Command to exec.
    my $add_headers = 0;                # Should we add headers.
    my $default_filename = undef;       # A default return filename to use.
    my $filename_parameter = undef;     # Which CGI parameter contains our filename.
    my $mime_type = undef;              # Override the mime type if you want.

    my $use_tmpfile = undef;            # Write to temporary file?
    my $tmp_directory = undef;          # Override default tmp file directory
    my $tmp_http_path = undef;          # Public HTTP address of tmp file dir
                                        #  (implies HTTP redirection, not streaming)
    my $tmp_redirect = 0;               # Are we going to redirect the user to the results?
    my $cleanup_after = 0;              # Cleanup after how many minutes?  0 = NEVER CLEANUP.

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    if ($axml->{'exec'}) {
        foreach my $exec (@{ $axml->{'exec'} }) {
            my $exec_ds = $exec->{'dataset'}->content;
            &Jarvis::Error::dump ($jconfig, "Comparing '$dataset' to '$exec_ds'.");
            next if (($dataset ne $exec_ds) && ($dataset !~ m/^$exec_ds\./));

            &Jarvis::Error::debug ($jconfig, "Found matching custom <exec> dataset '$dataset'.");

            $allowed_groups = $exec->{'access'}->content || die "No 'access' defined for exec dataset '$dataset'";
            $command = $exec->{'command'}->content || die "No 'command' defined for exec dataset '$dataset'";
            $add_headers = defined ($Jarvis::Config::yes_value {lc ($exec->{'add_headers'}->content || "no")});
            $default_filename = $exec->{'default_filename'}->content;
            $filename_parameter = $exec->{'filename_parameter'}->content || 'filename';
            $mime_type = $exec->{'mime_type'}->content;
            $cleanup_after = $exec->{'cleanup_after'}->content || 0;

            # If HTTP redirection URL is specified, then use of tmp files is forced.
            $tmp_directory = $exec->{'tmp_directory'}->content;
            $tmp_http_path = $exec->{'tmp_http_path'}->content;

            $use_tmpfile = $tmp_http_path || $tmp_directory || defined ($Jarvis::Config::yes_value {lc ($exec->{'use_tmpfile'}->content || "no")});
            $tmp_redirect = $tmp_http_path;

            # Override debug/dump.  Won't get much, but at least we'll see what is produced.
            $jconfig->{'dump'} = $jconfig->{'dump'} || defined ($Jarvis::Config::yes_value {lc ($exec->{'dump'}->content || "no")});
            $jconfig->{'debug'} = $jconfig->{'dump'} || $jconfig->{'debug'} || defined ($Jarvis::Config::yes_value {lc ($exec->{'debug'}->content || "no")});

            last;
        }
    }

    # If no match, that's fine.  Just say we couldn't do it.
    $command || return 0;

    # Check security.
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{'status'} = "401 Unauthorized";
        die "Wanted exec access: $failure";
    }

    # Get our parameters.  Note that our special variables like __username will
    # override sneaky user-supplied values.
    #
    my $cgi_params = $jconfig->{'cgi'}->Vars;

    # Figure out a filename.  It's not mandatory, if we don't have a default
    # filename and we don't have a filename_parameter supplied and defined then
    # we will return anonymous content in text/plain format.
    #
    my $filename = $cgi_params->{$filename_parameter} ? &File::Basename::basename ($cgi_params->{$filename_parameter}) : ($default_filename || undef);

    if (defined $filename) {
        &Jarvis::Error::debug ($jconfig, "Using filename '$filename'");

    } else {
        &Jarvis::Error::debug ($jconfig, "No return filename given.  MIME types and redirection will make best efforts.");
    }

    # If we're under windows, force the use of tmp files.
    $use_tmpfile = 1 if $^O eq "MSWin32";

    print STDERR &Dumper ($rest_args);

    # Now construct our safe variables from our CGI, rest and per-row (none) arguments.
    my %safe_params = &Jarvis::Config::safe_variables ($jconfig, $cgi_params, $rest_args, undef);

    my $tmp_file = undef;
    if ($use_tmpfile) {
        if ($tmp_directory) {
            if (-d $tmp_directory) {
                -w $tmp_directory || die "Cannot write to Exec temporary directory '$tmp_directory'.";

            } else {
                (mkdir $tmp_directory) || die "Cannot create Exec temporary directory '$tmp_directory'.";
            }
        }

        # NB: Only delete if we're streaming immediately.  If we're redirecting, keep file.
        my $template = $filename || "result.txt";
        my $suffix = undef;

        if ($template =~ s/(\.[a-z0-9]+)$//) {
            $suffix = $1;

        } else {
            $suffix = ".dat";
        }

        # Don't put the user session ID in the filename, it's tempting but it's actually a
        # security weakness.  Just add a random component.
        $template .= "-XXXXXXXXXX";

        $tmp_file = new File::Temp (
            TEMPLATE => $template,
            SUFFIX => $suffix,
            DIR => $tmp_directory,
            UNLINK => 0 #(! $tmp_http_path)
        );
        $safe_params{'__tmpfile'} = $tmp_file->filename;
        &Jarvis::Error::debug ($jconfig, "TMP filename = " . $tmp_file->filename);
    }

    # Add the dataset as a safe variable too.
    $safe_params{'__dataset'} = $dataset;

    # Add parameters to our command.  Note that we will take ALL parameters supplied
    # by the user, so we need to watch out for any funny business.
    foreach my $param (sort (keys %safe_params)) {

        # Quote param names AND values for the shell.
        my $param_value = $safe_params{$param};

        # Add a leading "p" for numeric parameters.
        if ($param =~ m/^[0-9]/) {

            # Check this doesn't conflict with an explicit "p1"!
            if (exists $safe_params{"p" . $param}) {
                &Jarvis::Error::debug ($jconfig, "Skipping numeric exec parameter '$param', it conflicts with explicit parameter 'p$param'.");
                next;
            }

            # Otherwise put a "p" on the front and pass it through.
            $param = "p" . $param;
        }
        &Jarvis::Error::debug ($jconfig, "Exec Parameter '$param' = '$param_value'");

        # MS Windows, we use double quotes.
        if ($^O eq "MSWin32") {
            $param = &escape_shell_windows ($param);
            $param_value = &escape_shell_windows ($param_value);
            $command .= " \"$param\"=\"$param_value\"";

        # These unix variants we use single quotes.
        } elsif (($^O eq "linux") || ($^O eq "solaris") || ($^O eq "darwin")) {
            $param = &escape_shell_unix ($param);
            $param_value = &escape_shell_unix ($param_value);
            $command .= " '$param'='$param_value'";

        # Not safe to continue.
        } else {
            die "Do not know how to escape Exec arguments for '$^O'.";
        }
    }

    # Set DEBUG if required.
    if ($jconfig->{'debug'}) {
        $ENV{'DEBUG'} = 1;
    }

    # Execute the command
    &Jarvis::Error::debug ($jconfig, "Executing Command: $command");
    my $output =`$command`;
    my $status = $?; # Failure?

    if ($status != 0) {
        # log command in case we haven't done so already
        &Jarvis::Error::log ($jconfig, "Executed Command: $command") unless ($jconfig->{'debug'});
        die "Command failed with status $status.\n$output";
    }

    # Are we supposed to add headers?  Does that include a filename header?
    # Note that if we really wanted to, we could squeeze in
    if ($add_headers && ! $tmp_redirect) {
        if (! $mime_type) {
            my $mime_types = MIME::Types->new;
            my $filename_type = $mime_types->mimeTypeOf ($filename);
            $mime_type = $filename_type ? $filename_type->type : 'text/plain';
        }
        &Jarvis::Error::debug ($jconfig, "Exec returning mime type '$mime_type'");

        if (defined $filename && ($filename ne '')) {
            if ($use_tmpfile) {
                my $length = -s $tmp_file->filename;
                print $jconfig->{'cgi'}->header(
                    -type                   => $mime_type,
                    'Content-Disposition'   => "attachment; filename=$filename",
                    -cookie                 => $jconfig->{'cookie'},
                    'Cache-Control'         => 'no-store, no-cache, must-revalidate',
                    'Content-Length'        => $length
                );
            } else {
                print $jconfig->{'cgi'}->header(
                    -type                   => $mime_type,
                    'Content-Disposition'   => "attachment; filename=$filename",
                    -cookie                 => $jconfig->{'cookie'},
                    'Cache-Control'         => 'no-store, no-cache, must-revalidate'
                );
            }

        } else {
            print $jconfig->{'cgi'}->header(
                -type => $mime_type,
                -cookie => $jconfig->{'cookie'},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
        }
    }

    # Now print the output.  If the report didn't add headers like it was supposed
    # to, then this will all turn to custard.

    # Option ONE - Pump out temporary file.
    #
    # Use this option if: use_tmpfile="yes" AND tmp_http_path is NOT defined.
    #
    # This appears to work under Windows/apache2 with HTTP, but isn't proven under
    # linux/apache2.  Also, under Windows/apache2/HTTPS/mod_perl it can result in an
    # "APR does not understand this error code" message which regular crashes Apache.
    #
    if ($use_tmpfile && ! $tmp_redirect) {
        &Jarvis::Error::debug ($jconfig, "Streaming temporary file content back to client.");
        open(F, $tmp_file->filename) || die "Unable to open '" . $tmp_file->filename . "' to return output to the client.";
        binmode(F);
        my $buff;
        while (read(F, $buff, 8 * 2**10)) {
            print STDOUT $buff;
        }
        close(F);

    # OPTION TWO - Redirect to temporary file.
    #
    # Use this option if: use_tmpfile="yes" AND tmp_http_path is defined.
    #
    # This should work in all cases.  BUT it does require that you have a process that
    # cleans up old temporary files.
    #
    } elsif ($tmp_redirect) {
        (-f $tmp_file->filename) || die "Report output failed, no file created.";

        my $url = "http://" . $ENV{"HTTP_HOST"} . "/" . $tmp_http_path . (($tmp_http_path =~ m|\/$|) ? "" : "/") . &File::Basename::basename ($tmp_file->filename);
        &Jarvis::Error::debug ($jconfig, "Redirect to: $url");
        print $jconfig->{'cgi'}->redirect( -URL => $url);

    # OPTION THREE - Just print out whatever was pumped back via STDOUT.
    #
    # Works fine under Linunx.  Under Windows this didn't seem to work, and we went
    # to temporary files instead.
    #
    } else {
        &Jarvis::Error::debug ($jconfig, "Printing exec STDOUT back to client STDOUT.");
        print $output;
    }

    # Cleanup if requested.
    if ($tmp_directory && ($cleanup_after > 0)) {
        &Jarvis::Error::debug ($jconfig, "Cleanup files in '$tmp_directory' older than $cleanup_after minutes.");

        # Not fatal if we can't cleanup.  Don't want to bother the user with our internal problems.
        opendir (my $dir, $tmp_directory) || (&Jarvis::Error::log ("Cannot opendir '$tmp_directory' for cleanup: $!") && return 1);
        my @files = grep { -f "$tmp_directory/$_" } readdir($dir);
        closedir $dir;

        # Loop each file and get file info.  If we can't, that probably means the file belongs to
        # somebody else in a shared /tmp directory.  Just ignore it and deal with those that are
        # our files.
        #
        foreach my $file (@files) {
            my @stat = stat "$tmp_directory/$file";
            next if ! @stat;
            next if ($> != $stat[4]);           # Only our files

            my $age = time() - $stat[9];
            next if ($age < $cleanup_after * 60);

            &Jarvis::Error::debug ($jconfig, "Cleanup '$file' with age $age seconds.");
            unlink "$tmp_directory/$file" || &Jarvis::Error::log ("Cannot cleanup '$file': $!");
        }
    }

    return 1;
}

1;
