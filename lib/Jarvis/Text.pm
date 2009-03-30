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
    our @EXPORT = qw (EscapeJavaScript EscapeSQL EscapeShell CleanName Trim);

    require Exporter;
}

###############################################################################
# Public Functions
###############################################################################

# ARGS: TextString
# Returns: Escape characters that will bother javascript.
sub EscapeJavaScript {
    my $text = $_[0];
    $text =~ s|\\|\\\\|og;
    $text =~ s|'|\\'|og;
    $text =~ s|"|\\"|og;
    $text =~ s|\n|\\n\\\n|osg;
    return $text;
}

# ARGS: TextString
# Returns: Escape characters that will bother a SQL '' string.
sub EscapeSQL {
    my $text = $_[0];
    $text =~ s|'|''|og;
    $text =~ s|\\|\\\\|og;
    return $text;
}

# ARGS: TextString
# Returns: Escape characters that will bother a Shell Exec '' string.
sub EscapeShell {
    my $text = $_[0];
    $text =~ s|'|'\\''|og;
    $text =~ s|\\|\\\\|og;
    return $text;
}

# ARGS: TextString
# Returns: Turn into a unique lowercase clean word.
sub CleanName {
    my $text = $_[0];
    $text = lc ($text);
    $text =~ s/\W+/_/g;
    $text =~ s/_+/_/g;
    $text =~ s/^_//g;
    $text =~ s/_$//g;    
    return $text;
}

# ARGS: TextString
# Returns: Trims leading and trailing whitespace.
sub Trim {
    my $text = $_[0];
    $text =~ s/^\s+//;
    $text =~ s/\s+$//g;
    return $text;
}

1;
