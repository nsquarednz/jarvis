#!/usr/bin/perl
###############################################################################
# Description:  SCALAR test cases for our custom XS JSON codec.
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
#       This software is Copyright 2019 by Jonathan Couper-Smartt.
###############################################################################
#
use strict;
use warnings;
use utf8;

use lib "../../../lib";

use boolean;

use XSLoader;
use Test::More;
use Test::Differences;
use Data::Dumper;
use Data::Compare;
use Data::Hexdumper;
use Getopt::Long;

use Jarvis::JSON::Utils;

################################################################################
# TEST CASES
################################################################################

my @tests = (
    { name => 'empty', json => "\n \t\r\n  ", error => "No JSON content found." },
    { name => 'null', json => "\n null  \t\r\n", expected => undef },
    { name => 'true', json => " true", expected => boolean::true },
    { name => 'false', json => " \nfalse ", expected => boolean::false },
    { name => 'false_junk', json => " \nfalse\n JUNK ", error => "Trailing non-whitespace begins at byte offset 9." },
    { name => 'integer', json => "3 ", expected => 3 },
    { name => 'negative', json => "-732344 ", expected => -732344 },
    { name => 'fraction', json => "  7234.123423142 ", expected => 7234.123423142 },
    { name => 'exp1', json => " -1234.44e12 ", expected => -1234.44e12 },
    { name => 'exp2', json => " 0.34243E-4 ", expected => 0.34243E-4 },
    { name => 'empty', json => '""', expected => '' },
    { name => 'unterminated', json => ' "Unterminated\n String', error => "Unterminated string beginning at byte offset 1." },
    { name => 'simple', json => '" A simple String "', expected => ' A simple String ' },
    { name => 'utf8', json => '" UTF sö € string𝄞"', expected => ' UTF sö € string𝄞' },
    { name => 'multi-line', json => '" UTF sö € 
multi-line string
"', expected => ' UTF sö € 
multi-line string
' },
    { name => 'escapes1', json => '" \\\\ \\" \\/ "', expected => ' \\ " / ' },
    { name => 'escapes2', json => '" \\b \\f \\r \\n \\t "', expected => " \b \f \r \n \t " },
    { name => 'escapes3', json => '"\\x0D\\x3a\\xd6\\x20"', expected => "\r:Ö " },
    { name => 'escapes4', json => '"\\u003A\\u00D6\\u0FD0\\uD2Cf\\U01D11e"', expected => ":Ö࿐틏𝄞" },
    { name => 'mixed', json => ' "\\u003A\\u00D6\\u0FD0\\uD2Cf\\U01D11e\\x91"', error => "Forbidden mix of 8-bit \\x (binary) with UTF-8 content in string starting at byte offset 1." },
);

my $ntests = 0;

################################################################################
# Trace and flags.
################################################################################

my $leak = 0;
&Getopt::Long::GetOptions ("leak" => \$leak) || die "usage: perl $0 [--leak]";

if ($leak) { use Devel::Leak; };

################################################################################
# Initialise Leak Checker
################################################################################

my $count = $leak && Devel::Leak::NoteSV (my $handle);

################################################################################
# ALL THE OTHER TESTS
################################################################################

foreach my $i (1 .. ($leak ? 5 : 1)) {
foreach my $test (@tests) {
    my $result = undef;
    my $error = undef;

    eval {
        $result = Jarvis::JSON::Utils::decode ($test->{json});
    };
    if ($@) {
        $error = $@;
        $error =~ s/ at \w+\.pl line \d+\..*$//s;
    }

    if (! $leak) {
        if (defined $error) {
            if (!ok (&Compare ($test->{error}, $error), "TEST ($test->{name})")) {
                printf STDERR "Error does not match, expected = ";
                print STDERR $test->{error} ? "$test->{error}\n" : "NO ERROR\n";
                printf STDERR "What we got = ";
                print STDERR "$error\n";
            }

        } else {
            if (!ok (&Compare ($test->{expected}, $result), "TEST ($test->{name})")) {
                printf STDERR "Result does not match, expected = ";
                $test->{expected} and print STDERR hexdump ($test->{expected}, { suppress_warnings => 1 }) . "\n";
                printf STDERR "What we got = ";
                $result and print STDERR hexdump ($result, { suppress_warnings => 1 }) . "\n";
            }
        }
    }
    #utf8::is_utf8 ($result) and print STDERR "String is UTF-8.\n";
    #$result and print STDERR hexdump ($result, { suppress_warnings => 1 }) . "\n";
    #$error and print STDERR "ERROR = $error\n";
    $ntests++;
}
}

################################################################################
# Finish Testing
################################################################################

$leak || done_testing ($ntests);

if ($leak) {
    my $count2 = Devel::Leak::CheckSV ($handle);
    print "GAINED: " . ($count2 - $count) . "\n";
}

1;