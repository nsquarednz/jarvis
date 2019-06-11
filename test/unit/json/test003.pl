#!/usr/bin/perl
###############################################################################
# Description:  HASH test cases for our custom XS JSON codec.
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
# TEST CASES
################################################################################

my @tests = (
    { name => 'empty', json => " {} ", expected => {} },
    { name => 'empty_junk', json => " {\n \n} JUNK\n\n", error => "Trailing non-whitespace begins at byte offset 7." },
    { name => 'endless', json => " {\n ", error => "Object element starting at byte offset 1 has no matching '}'." },
    { name => 'basic', json => ' { "ABC": 34 } ', expected => { ABC => 34 } },
    { name => 'double', json => ' { "ABC": 34, "ç": "é", "asdf-\x67": "asdf-\x67", "yes": true, "NO!": false, "maybe?": null } ', expected => { ABC => 34 } },
);

my $ntests = 0;

# Use s/// once so that its buffer is allocated.
$ntests =~ s/AB/B/;

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
                print STDERR &Dumper ($test->{expected});
                printf STDERR "What we got = ";
                print STDERR &Dumper ($result);
                $error and print STDERR "$error\n";
            }
        }
    }
    #utf8::is_utf8 ($result) and print STDERR "String is UTF-8.\n";
    #$result and print &Dumper ($result);
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