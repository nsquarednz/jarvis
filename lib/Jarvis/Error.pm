###############################################################################
# Description:  Error logging functions - Debug, Log.  Also a MyDie function
#               which calls "die" but with some extra session info prepended
#               to the die message string.
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
#       $msg - User message string.
#       $level - "log", "error", etc.
#       %args - Hash of Args (* indicates mandatory)
#           user_name, app_name, dataset_name
#
# Returns:
#       dies
################################################################################
#
sub DumpString {
    my ($msg, $level, %args) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Sep', 'Oct', 'Nov', 'Dec');

    my $header = sprintf "[%s %s %d %02d:%02d:%02d %04d] [$level] ",
        $days[$wday], $months[$mon], $mday, $hour, $min, $sec, $year + 1900;

    $header .= "[" . $$;
    (defined $args{'app_name'}) && ($header .= "/" . $args{'app_name'});
    (defined $args{'user_name'}) && ($header .= "/" . $args{'user_name'});
    (defined $args{'dataset_name'}) && ($header .= "/" . $args{'dataset_name'});
    $header .= "] ";

    $msg = &Trim ($msg);
    if ($msg !~ m/\n$/) {
        $msg .= "\n";
    }
    $header && (length ($msg) + length ($header) > 132) && ($header .= "\n");

    return "$header$msg";
}

################################################################################
# Dies with some standard "where are we" info.
#
# Params:
#       %args - Hash of Args (* indicates mandatory)
#           user_name, app_name, dataset_name
#
# Returns:
#       dies
################################################################################
#
sub MyDie {
    my ($msg, %args) = @_;

    die &DumpString ($msg, 'fatal', %args);
}

################################################################################
# Same but just debug.
#
# Params: Same as MyDie.
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub Debug {
    my ($msg, %args) = @_;

    $args{'debug'} || return;

    print STDERR &DumpString ($msg, 'debug', %args);
}

################################################################################
# Same as debug, but always prints.
#
# Params: Same as MyDie and Debug.
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub Log {
    my ($msg, %args) = @_;

    print STDERR &DumpString ($msg, 'log', %args);
}

1;
