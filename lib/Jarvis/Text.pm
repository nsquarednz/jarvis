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
                      escape_shell_windows trim word2html nonascii);

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

# ARGS: TextString
# Returns: String with all MS Word characters converted to ASCII or HTML equivalents.
#          This is far from perfect.  I would be pretty confident that Word produces
#          other oddball characters out there.  Feel free to add to this list.
sub word2html {
    my $text = $_[0];

    $text =~ s|\xe2\x80\x93|&ndash;|og;    # Long dash
    $text =~ s|\xe2\x80\x94|&mdash;|og;    # Longer dash
    $text =~ s|\xe2\x80\x99|'|og;    # Fancy forward/back quotes.  Blech!
    $text =~ s|\xe2\x80\x9c|"|og;
    $text =~ s|\xe2\x80\x9d|"|og;
    $text =~ s|\xe2\x80\xA2|*|og;
    $text =~ s|\xA1|&iexcl;|og;
    $text =~ s|\xA3|&pound;|og;
    $text =~ s|\xA9|&copy;|og;
    $text =~ s|\xAE|&reg;|og;
    $text =~ s|\xB2|&sup2;|og;
    $text =~ s|\xB3|&sup3;|og;
    $text =~ s|\xB4|'|og;            # Technically &acute; but ' is fine.
    $text =~ s|\xBD|&frac12;|og;
    $text =~ s|\xBE|&frac34;|og;
    $text =~ s|\xC1|&Aacute;|og;
    $text =~ s|\xC2|&Acirc;|og;
    $text =~ s|\xC3|&Atilde;|og;
    $text =~ s|\xE0|&agrave;|og;
    $text =~ s|\xE1|&aacute;|og;
    # \xE2 is &acirc;, but don't replace that, because it conficts with the three-char UTF!
    $text =~ s|\xE7|&ccedil;|og;
    $text =~ s|\xE8|&egrave;|og;
    $text =~ s|\xED|&iacute;|og;
    $text =~ s|\xE9|&eacute;|og;
    $text =~ s|\xEA|&ecirc;|og;
    $text =~ s|\xEF|&iuml;|og;
    $text =~ s|\xF1|&ntilde;|og;
    $text =~ s|\xF3|&oacute;|og;
    $text =~ s|\xF4|&ocirc;|og;
    $text =~ s|\xFA|&uacute;|og;
    $text =~ s|\xFC|&uuml;|og;
    $text =~ s|\x85|...|og;
    $text =~ s|\x91|'|og;
    $text =~ s|\x92|'|og;
    $text =~ s|\x93|"|og;
    $text =~ s|\x94|"|og;
    $text =~ s|\x96|&ndash;|og;
    $text =~ s|\x97|&mdash;|og;
    $text =~ s|\x99|&trade;|og;
    $text =~ s|\&\#8216\;|'|og;
    $text =~ s|\&\#8217\;|'|og;

    # We've done our best.  Brute force the rest.
    sub hexchar { return "&#x" . (sprintf "%02x", ord (shift)) . ";" }
    $text =~ s/([^\w\d\s!"#\$\%&'\(\)\*\+,\-\.\/:;<=>\?\@\[\\\]\^\`\{\|}~��������������������������������������������������������������������������������������������������������������������������])/hexchar($1)/esg;

    return $text;
}

1;
