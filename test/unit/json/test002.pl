#!/usr/bin/perl
###############################################################################
# Description:  ARRAY test cases for our custom XS JSON codec.
#               Also tests for comments.
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

my @tests = (
    { name => 'empty', json => " [\n\n] ", expected => [] },
    { name => 'empty_junk', json => " [\n \n] JUNK\n\n", error => "Trailing non-whitespace begins at byte offset 7." },
    { name => 'array', json => " [ 34, 7, \"YES\nOR NO\" ] ", expected => [ 34, 7, "YES\nOR NO" ] },
    { name => 'array_nested', json => " [ 34, [ 7, true, null ], \"YES\nOR NO\" ] ", expected => [ 34, [ 7, boolean::true, undef ], "YES\nOR NO" ] },
    {   
        name => 'array_nested_comment1', json => 
"#Comment in Perl Style
[ 34,// CSTYLE ça va comme ca?
[ 7, true, null ], -- SQL STYLE comment --
\"YES -- No Comment  
OR NO\" ] ", 
        expected => [ 34, [ 7, boolean::true, undef ], "YES -- No Comment  \nOR NO" ] 
    },
);

my $ntests = 0;

################################################################################
# Initialise Leak Checker
################################################################################

my $count = $leak && Devel::Leak::NoteSV (my $handle);

################################################################################
# ALL THE OTHER TESTS
################################################################################

foreach my $test (@tests) {
    my $result = undef;
    my $error = undef;
    undef $@;

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
    utf8::is_utf8 ($result) and print STDERR "String is UTF-8.\n";
    $result and print &Dumper ($result);
    $ntests++;
}

################################################################################
# Finish Testing
################################################################################

$leak || done_testing ($ntests);

$leak && Devel::Leak::CheckSV ($handle);

1;