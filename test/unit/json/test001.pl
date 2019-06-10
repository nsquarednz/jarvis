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

use lib "../../../lib";

use boolean;

use XSLoader;
use Test::More;
use Test::Differences;
use Data::Dumper;
use Data::Compare;
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

my $JSON_TEST1A = "   
\t\r
";

my $JSON_TEST1B = " null
";

my $JSON_TEST1C = " true ";

my $JSON_TEST1D = "false";

################################################################################
# Initialise Leak Checker
################################################################################

my $count = $leak && Devel::Leak::NoteSV (my $handle);

################################################################################
# TEST 1A - nothing.
################################################################################

my $expected = "No JSON content found.";

eval {
    Jarvis::JSON::Utils::decode ($JSON_TEST1A);
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

################################################################################
# TEST 1B - null.
################################################################################

$expected = undef;

$result = Jarvis::JSON::Utils::decode ($JSON_TEST1B);

if (! $leak) {
    if (!ok (&Compare ($expected, $result), "TEST 1B (null)")) {
        printf STDERR "Result does not match, expected = ";
        print STDERR &Dumper ($expected);
        printf STDERR "What we got = ";
        print STDERR &Dumper ($result);
    }
}

################################################################################
# TEST 1C - true.
################################################################################

$expected = boolean::true;

$result = Jarvis::JSON::Utils::decode ($JSON_TEST1C);

if (! $leak) {
    if (!ok (&Compare ($expected, $result), "TEST 1C (true)")) {
        printf STDERR "Result does not match, expected = ";
        print STDERR &Dumper ($expected);
        printf STDERR "What we got = ";
        print STDERR &Dumper ($result);
    }
}

################################################################################
# TEST 1D - false.
################################################################################

$expected = boolean::false;

$result = Jarvis::JSON::Utils::decode ($JSON_TEST1D);

if (! $leak) {
    if (!ok (&Compare ($expected, $result), "TEST 1D (false)")) {
        printf STDERR "Result does not match, expected = ";
        print STDERR &Dumper ($expected);
        printf STDERR "What we got = ";
        print STDERR &Dumper ($result);
    }
}

################################################################################
# Finish Testing
################################################################################

undef $result;
undef $expected;
undef $@;

$leak || done_testing (4);

$leak && Devel::Leak::CheckSV ($handle);

1;