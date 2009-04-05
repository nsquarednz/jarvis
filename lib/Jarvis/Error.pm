###############################################################################
# Description:  Error logging functions - Debug, Log.  Also a my_die function
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
#       $jconfig - Jarvis::Config object
#           READ: username, app_name, dataset_name
#       $msg - User message string. We will extend with extra info from $jconfig.
#       $level - "log", "error", etc.
#
# Returns:
#       dies
################################################################################
#
sub dump_string {
    my ($jconfig, $level, $msg) = @_;

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Sep', 'Oct', 'Nov', 'Dec');

    my $header = sprintf "[%s %s %d %02d:%02d:%02d %04d] [$level] ",
        $days[$wday], $months[$mon], $mday, $hour, $min, $sec, $year + 1900;

    $header .= "[" . $$;
    ($jconfig->{'app_name'}) && ($header .= "/" . $jconfig->{'app_name'});
    ($jconfig->{'username'}) && ($header .= "/" . $jconfig->{'username'});
    ($jconfig->{'dataset_name'}) && ($header .= "/" . $jconfig->{'dataset_name'});
    $header .= "] ";

    # This newline is tidy.  It also stops Perl from appending an "at line..."
    # to the message if/when we die with this message.
    #
    $msg = &trim ($msg) . "\n";

    $header && (length ($msg) + length ($header) > 132) && ($header .= "\n");

    return "$header$msg";
}

################################################################################
# Dies with some standard "where are we" info.  Uses dump_string.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $msg - Message to print
#       $level - Optional level override.
#
# Returns:
#       dies
################################################################################
#
sub my_die {
    my ($jconfig, $msg, $level) = @_;

    die &dump_string ($jconfig, $level || 'fatal', $msg);
}

################################################################################
# Same but just debug.  Uses dump_string.
#
# Params: Same as my_die.
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub debug {
    my ($jconfig, $msg) = @_;

    $jconfig->{'debug'} || return;

    print STDERR &dump_string ($jconfig, 'debug', $msg);
}

################################################################################
# Same as debug, but always prints.  Uses dump_string.
#
# Params: Same as my_die and Debug.
#
# Returns:
#       Prints to STDERR and returns 1.
################################################################################
#
sub log {
    my ($jconfig, $msg) = @_;

    print STDERR &dump_string ($jconfig, 'log', $msg);
}

1;
