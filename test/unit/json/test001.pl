#!/usr/bin/perl
###############################################################################
# Description:  Test cases for our custom XS JSON codec.
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

XSLoader::load ('Jarvis::JSON::Utils');

################################################################################
# Trace and flags.
################################################################################

my $leak = 0;
&Getopt::Long::GetOptions ("leak" => \$leak) || die "usage: perl $0 [--leak]";

if ($leak) { use Devel::Leak; };

################################################################################
# Load LUA.
################################################################################

my $JSON_TEST_1A = "\n \t\r\n  ";

my @tests = (
    { name => 'null', json => "\n null  \t\r\n", expected => undef },
    { name => 'true', json => " true", expected => boolean::true },
    { name =>'false', json => " \nfalse ", expected => boolean::false },
    { name => 'integer', json => "3 ", expected => 3 },
    { name => 'negative', json => "-732344 ", expected => -732344 },
    { name => 'fraction', json => "  7234.123423142 ", expected => 7234.123423142 },
    { name => 'exp1', json => " -1234.44e12 ", expected => -1234.44e12 },
    { name => 'exp2', json => " 0.34243E-4 ", expected => 0.34243E-4 },
    { name => 'empty', json => '""', expected => '' },
    { name => 'simple', json => '" A simple String "', expected => ' A simple String ' },
    { name => 'utf8', json => '" UTF sö € string𝄞"', expected => ' UTF sö € string𝄞' },
    { name => 'multi-line', json => '" UTF sö € 
multi-line string
"', expected => ' UTF sö € 
multi-line string
' },
    { name => 'escapes1', json => '" \\\\ \\" \\/ "', expected => ' \\ " / ' },
    { name => 'escapes2', json => '" \\b \\f \\r \\n \\t "', expected => " \b \f \r \n \t " },
    { name => 'escapes3', json => '"\\u003A\\u00D6\\u0FD0\\uD2Cf\\U01D11e"', expected => ":Ö࿐틏𝄞" },
);

my $ntests = 0;

################################################################################
# Initialise Leak Checker
################################################################################

my $count = $leak && Devel::Leak::NoteSV (my $handle);

################################################################################
# TEST 1A - nothing.
################################################################################

my $expected = "No JSON content found.";

eval {
    Jarvis::JSON::Utils::decode ($JSON_TEST_1A);
};
my $result = $@;
defined ($result) or die "Unexpected Success!";
$result =~ s/ at .*\.pl line \d+\..*$//s;

if (! $leak) {
    if (!ok (&Compare ($expected, $result), "TEST 1A (empty)")) {
        printf STDERR "Result does not match, expected = ";
        print STDERR &Dumper ($expected);
        printf STDERR "What we got = ";
        print STDERR &Dumper ($result);
    }
}
$ntests++;

################################################################################
# ALL THE OTHER TESTS
################################################################################

foreach my $test (@tests) {
    $expected = $test->{expected};

    $result = Jarvis::JSON::Utils::decode ($test->{json});

    if (! $leak) {
        if (!ok (&Compare ($expected, $result), "TEST ($test->{name})")) {
            printf STDERR "Result does not match, expected = ";
            print STDERR &Dumper ($expected);
            printf STDERR "What we got = ";
            print STDERR &Dumper ($result);
        }
    }
    $result and print STDERR hexdump ($result, { suppress_warnings => 1 }) . "\n";
    $ntests++;
}

################################################################################
# Finish Testing
################################################################################

undef $result;
undef $expected;
undef $@;

$leak || done_testing ($ntests);

$leak && Devel::Leak::CheckSV ($handle);

1;