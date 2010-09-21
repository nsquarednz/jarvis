###############################################################################
# Description:  Text manipulation functions used by Jarvis routines.
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

package Jarvis::Text;

BEGIN {
    our @ISA = qw (Exporter);
    our @EXPORT = qw (escape_java_script escape_sql escape_shell_unix
                      escape_shell_windows trim);

    require Exporter;
}

###############################################################################
# Public Functions
###############################################################################

# ARGS: TextString
# Returns: Escape characters that will bother javascript in a " string ".
sub escape_java_script {
    my $text = $_[0];
    $text =~ s|\\|\\\\|og;
    $text =~ s|"|\\"|og;
    $text =~ s|\n|\\n|osg;
    return $text;
}

# ARGS: TextString
# Returns: Escape characters that will bother a SQL '' string.
sub escape_sql {
    my $text = $_[0];
    $text =~ s|\\|\\\\|og;
    $text =~ s|'|''|og;
    return $text;
}

# ARGS: TextString
# Returns: Escape characters that will bother a Unix Shell Exec '' string.
sub escape_shell_unix {
    my $text = $_[0];
    $text =~ s|\\|\\\\|og;
    $text =~ s|'|'\\''|og;
    return $text;
}

# ARGS: TextString
# Returns: Escape characters that will bother a Windows Shell Exec "" string.
sub escape_shell_windows {
    my $text = $_[0];
    $text =~ s|\\|\\\\|og;
    $text =~ s|"|\\"|og;
    return $text;
}

# ARGS: TextString
# Returns: trims leading and trailing whitespace.
sub trim {
    my $text = $_[0];
    $text =~ s/^\s+//o;
    $text =~ s/\s+$//og;
    return $text;
}

1;
