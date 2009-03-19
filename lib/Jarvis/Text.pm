#NOT FOR RUNNING AS CGI
#
# Description:  Text manipulation functions used by Jarvis routines.
#
###############################################################################
#
use strict;
use warnings;

package Jarvis::Text;

BEGIN {
    our @ISA = qw (Exporter);
    our @EXPORT = qw (EscapeJavaScript CleanName Trim);

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
