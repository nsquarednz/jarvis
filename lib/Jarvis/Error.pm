###############################################################################
# Description:  Error logging functions - Debug, Log.  If you want to die,
#               just call "die".  We will take care of that elsewhere.
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

package Jarvis::Error;

use Jarvis::Text;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Makes a standard message to print out.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ: username, app_name, dataset_name, dbgfmt
#       $msg - User message string. We will extend with extra info from $jconfig.
#       $level - "log", "error", etc.
#
#       dbgmask contains specifies the headers to include:
#           '%T' -> Timestamp
#           '%L' -> Level
#           '%U' -> Username
#           '%D' -> Dataset
#           '%A' -> Application
#           '%P' -> Pid
#           '%M' -> Message
#
#       Default dbmask is in Config.pm.
#
# Returns:
#       dies
################################################################################
#
sub print_message {
    my ($jconfig, $level, $msg) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
    my $timestamp = sprintf "%s %s %d %02d:%02d:%02d %04d", $days[$wday], $months[$mon], $mday, $hour, $min, $sec, $year + 1900;
    $msg =~ s/\s*$/\n/;

    my @bits = split ( /\%([TLUDAPM])/i, ($jconfig->{'log_format'} || '[%P/%A/%U/%D] %M'));
    my $output = '';

    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            if ($bits[$idx] eq 'T') {
                $output .= $timestamp;

            } elsif ($bits[$idx] eq 'L') {
                $output .= $level;

            } elsif ($bits[$idx] eq 'U') {
                $output .= $jconfig->{'username'} || '';

            } elsif ($bits[$idx] eq 'D') {
                $output .= $jconfig->{'dataset_name'} || '';

            } elsif ($bits[$idx] eq 'A') {
                $output .= $jconfig->{'app_name'} || '';

            } elsif ($bits[$idx] eq 'P') {
                $output .= $$;

            } elsif ($bits[$idx] eq 'M') {
                $output .= $msg;
            }

        } else {
            $output .= $bits[$idx];
        }
    }

    return $output;
}

################################################################################
# Same but just debug.  Uses print_message.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $msg - Message to print
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub debug {
    my ($jconfig, $msg) = @_;

    $jconfig->{'debug'} || return;

    print STDERR &print_message ($jconfig, 'debug', $msg);
}

################################################################################
# Used for debug that might produce LOTS of output.  Needs to be enabled
# separately with dump="yes".
#
# Params:
#       $jconfig - Jarvis::Config object
#       $msg - Message to print
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub dump {
    my ($jconfig, $msg) = @_;

    $jconfig->{'dump'} || return;
    print STDERR &print_message ($jconfig, 'dump', $msg);
}

################################################################################
# Same as debug, but always prints.  Uses print_message.
#
# Params: Same as Debug.
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub log {
    my ($jconfig, $msg) = @_;

    print STDERR &print_message ($jconfig, 'log', $msg);
}

1;
