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

use Data::Dumper;
use Encode qw (_utf8_off _utf8_on);
use Time::HiRes;

use Jarvis::Text;

# I don't like the way that Data::Dumper decides to print its non-printable
# strings.  It uses octal for bytes that it doesn't like.  But in telephony
# we prefer hex.  Also if one byte in a string is hex, it's a pretty good 
# indicator that all the other bytes are probably hex as well, and should
# be reported as such.
{
    no warnings 'redefine';
    sub Data::Dumper::qquote {
        return "'" . &Jarvis::Error::printable (shift) . "'";
    }
}

###############################################################################
# Perform environment-specific UTF-8 printing.
#
# Both standard and fast CGI will warn if we attempt to print content
# containing UTF-8.
#
#   standard: "Wide character in print..."
#   fast: "Use of wide characters in FCGI::Stream::PRINT..."
#
# The warnings break output, so we can't just ignore them!
#
# With standard CGI we can use binmode to solve the problem.
#
# Unfortunately fast CGI uses tied handles which don't honour binmode:
#   https://www.apachelounge.com/viewtopic.php?p=37483
#
# So for fast CGI we assume the content of $string_ref is [already] UTF-8
# encoded. Therefore we do not have to encode again. We can simply clear the
# internal UTF-8 flag that Fast CGI trips over.
#
# Parameters:
#       $string_ref - A reference to the string to print.
#       $stream - The stream to print to. Defaults to STDOUT.
#
# Returns:
#       <nothing>
###############################################################################
#
my $is_fast_cgi = undef;
sub print_utf8 {
    my ($string_ref, $stream) = @_;
    $stream //= *STDOUT;
    if (!defined $is_fast_cgi) {
        my $h = $CGI::Fast::Ext_Request;
        $is_fast_cgi = (defined $h && ref($h) && $h->IsFastCGI()) ? 1 : 0;
    }
    if ($is_fast_cgi) {
        my $was_utf8 = _utf8_off($$string_ref);
        print $stream $$string_ref;
        _utf8_on(${$string_ref}) if ($was_utf8); 
    } else {
        # We enable binmode for STDERR globally in agent.pl.
        if ($stream eq *STDOUT) {
            binmode $stream, ':utf8';
        }
        print $stream $$string_ref;
    }
}

###############################################################################
# PRINTABLE
#       Return a nice debug printable version of a string.
#
# Parameters:
#       $value - Value to make printable.
#
# Returns:
#       $printable - Version that won't mess up your terminal.
###############################################################################
sub printable {
    my ($value) = @_;
    
    if (! defined $value) {
        return '<undef>';
    }
    
    # If it contains any 'odd' characters, print as HEX.  Maybe truncated.    
    if ($value =~ m/[^\n\r\t\x20-\x7e]/s) {       
        my $hex = $value;
        $hex =~ s/(.)/'\x'.sprintf("%02x", ord ($1))/egs;
        return $hex;
        
    # Otherwise just plain, maybe truncated.
    } else {
        my $len = length ($value);
        $value =~ s/\\/\\\\/;
        $value =~ s/'/\\'/;
        return $value;
    }
}

################################################################################
# Generates an error message to send to the client over HTTP.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ: username, app_name, dataset_name
#       $format - The format to use when formatting our response message
#       $msg - User message string. We will extend with extra info from $jconfig.
#       $level - "log", "error", etc.
#       @params - Optional params to be "sprintf" written into $msg.
#
#       dbgmask contains specifies the headers to include:
#           '%T' -> Timestamp
#           '%L' -> Level
#           '%U' -> Username
#           '%D' -> Dataset
#           '%A' -> Application
#           '%P' -> Pid
#           '%M' -> Message
#           '%S' -> Session ID
#           '%R' -> Request ID
#
#       Default dbmask is in Config.pm.
#
# Returns:
#       The error string to present to the client.
################################################################################
#
sub print_message {
    my ($jconfig, $format, $level, $msg, @params) = @_;

    use integer;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    my (undef,$micsec) = Time::HiRes::gettimeofday();
    my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
    my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
    my $timestamp = sprintf "%s %s %d %02d:%02d:%02d %04d", $days[$wday], $months[$mon], $mday, $hour, $min, $sec, $year + 1900;
    my $hires_timestamp = sprintf "%s %s %d %02d:%02d:%02d.%06d %04d", $days[$wday], $months[$mon], $mday, $hour, $min, $sec, $micsec, $year + 1900;

    if (scalar @params) {
        @params = map { &printable($_); } @params; 
        $msg = sprintf ($msg, @params);
    }
    $msg =~ s/\s*$/\n/;

    my @bits = split ( /\%([THLUDAPMRS])/i, ($format || '[%P/%A/%U/%D][%R] %M'));
    my $output = '';

    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            if ($bits[$idx] eq 'T') {
                $output .= $timestamp;

            } elsif ($bits[$idx] eq 'H') {
                $output .= $hires_timestamp;

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

            } elsif ($bits[$idx] eq 'R') {
                $output .= $jconfig->{request_id} || '';
            
            } elsif ($bits[$idx] eq 'S') {
                $output .= $jconfig->{sid} || '';
            }
        } else {
            $output .= $bits[$idx];
        }
    }

    return $output;
}

################################################################################
# Prints a standard-format message to STDERR. Uses the log_format from the
# Jarvis config. Uses print_message and print_utf8.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ: username, app_name, dataset_name, log_format
#       $msg - User message string. We will extend with extra info from $jconfig.
#       $level - "log", "error", etc.
#       @params - Optional params to be "sprintf" written into $msg.
#
#       log_format contains specifies the headers to include. See print_message
#       for more information
#
#       Default dbmask is in Config.pm.
#
# Returns:
#       <nothing>
################################################################################
#
sub print_log_message {
    my ($jconfig, $level, $msg, @params) = @_;
    my $string = &print_message ($jconfig, $jconfig->{log_format}, $level, $msg, @params);
    print_utf8 (\$string, *STDERR);
}

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Print debug/dump/log output to STDERR.  Uses print_log_message.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $msg - Message to print
#       @params - Optional params to be "sprintf" written into $msg.
#
# Returns:
#       <nothing>
################################################################################
#
sub debug {
    my ($jconfig, $msg, @params) = @_;

    $jconfig->{'debug'} || return;
    &print_log_message ($jconfig, 'debug', $msg, @params);
}
sub dump {
    my ($jconfig, $msg, @params) = @_;

    $jconfig->{'dump'} || return;
    &print_log_message ($jconfig, 'dump', $msg, @params);
}
sub log {
    my ($jconfig, $msg, @params) = @_;

    &print_log_message ($jconfig, 'log', $msg, @params);
}

################################################################################
# Dump a hash/array/constant similar to Dump.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $var - Variable to dump in structured format.
#
# Returns:
#       <nothing>
################################################################################
#
sub debug_var {
    my ($jconfig, $var) = @_;
    
    $jconfig->{'debug'} || return;
    &print_var ($jconfig, 'debug', $var);
}
sub dump_var {
    my ($jconfig, $var) = @_;
    
    $jconfig->{'dump'} || return;
    &print_var ($jconfig, 'dump', $var);
}
sub log_var {
    my ($jconfig, $var) = @_;
    
    &print_var ($jconfig, 'log', $var);
}
sub print_var {
    my ($jconfig, $level, $var) = @_;
    
    my $dumper = Data::Dumper->new([$var]);
    my $var_dump = $dumper->Useqq(1)->Terse(1)->Indent(1)->Sortkeys(1)->Dump ();
    foreach my $msg (split ("\n", $var_dump)) {
        &print_log_message ($jconfig, $level, $msg);
    }
}

################################################################################
# Dump a hash/array/constant similar to Dump.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $msg - Binary block to print in hex.
#
# Returns:
#       <nothing>
################################################################################
#
sub debug_hex {
    my ($jconfig, $msg) = @_;
    
    $jconfig->{'debug'} || return;
    &print_hex ($jconfig, 'debug', $msg);
}
sub dump_hex {
    my ($jconfig, $msg) = @_;
    
    $jconfig->{'dump'} || return;
    &print_hex ($jconfig, 'dump', $msg);
}
sub log_hex {
    my ($jconfig, $msg) = @_;
    
    &print_hex ($jconfig, 'log', $msg);
}
sub print_hex {
    my ($jconfig, $level, $msg) = @_;
    
    if (! defined $msg) {
        &print_log_message ($jconfig, $level, "  <undef>");
        
    } else {
        my $msglen = length ($msg);
        for (my $pos = 0; $pos < $msglen; $pos = $pos + 16) {
            my $hex = join (" ", unpack ("(H2)*", substr ($msg, $pos, 16)));
            &print_log_message ($jconfig, $level, "  " . $hex);
        }
    }
}

1;
