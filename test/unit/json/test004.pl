#!/usr/bin/perl
###############################################################################
# Description:  Variable substitution tests.
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

# Some random variables to substitute.
my $values = {
    ABC => 34,
    # -234.6,
    # "ç",
    # "\x01\x02",
    # [ 1, 2, 3 ],
    # { k => 'v' },
    # undef,
    "çimple!true!NI" => boolean::true,
    "(ABC.FALSE)" => boolean::false,
};

my @tests = (
    { name => 'topvar', json => " \$ABC ", expected => "ABC", error => "Variable not permitted at top level, starting at byte offset 1." },
    { name => 'empty', json => " [ \$\$ ] ", error => "Empty variable specifier detected at byte offset 3." },
    { name => 'unterm_var1', json => " [ \n\$asdf", error => "Unterminated variable specifier beginning at byte offset 4." },
    { name => 'unterm_var2', json => ' [ $asdf', error => "Unterminated variable specifier beginning at byte offset 3." },
    { name => 'unterm_array', json => ' [ $asdf$', error => "Array element starting at byte offset 1 has no matching ']'." },
    { name => 'unquoted', json => '{ "limit": $limit|__LIMIT$, projection: { "name": 1 } }', error => "Object name not found at byte offset 28." },
    { name => 'aref', json => ' [ $ABC$ ] ', expected => [ undef ], evars => [ { name => "ABC", vref => \undef } ], after => [ 34 ] },
    { name => 'nested', json => ' [ { "FROG": $çimple!true!NI$, "ANT": $(ABC.FALSE)$, } ] ', 
        expected => [ { "FROG" => undef, "ANT" => undef } ], 
        evars => [ { name => "çimple!true!NI", vref => \undef }, { name => "(ABC.FALSE)", vref => \undef } ], 
    after => [ { "FROG" => boolean::true, "ANT" => boolean::false } ] },
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
    my $vars = [];

    eval {
        $result = Jarvis::JSON::Utils::decode ($test->{json}, $vars);
    };
    if ($@) {
        $error = $@;
        $error =~ s/ at \w+\.pl line \d+\..*$//s;
    }

    if (! $leak) {
        if (defined $error) {
            $ntests++;
            if (!ok (&Compare ($test->{error}, $error), "TEST ($test->{name})")) {
                printf STDERR "Error does not match, expected = ";
                print STDERR $test->{error} ? "$test->{error}\n" : "NO ERROR\n";
                printf STDERR "What we got = ";
                print STDERR "$error\n";
            }

        } else {
            $ntests++;
            if (!ok (&Compare ($test->{expected}, $result), "TEST ($test->{name}) Returned")) {
                printf STDERR "Result does not match, expected = ";
                print STDERR &Dumper ($test->{expected});
                printf STDERR "What we got = ";
                print STDERR &Dumper ($result);
            }

            if (defined $test->{evars}) {
                $ntests++;
                if (!ok (&Compare ($test->{evars}, $vars), "TEST ($test->{name}) Vars")) {
                    printf STDERR "Result does not match, expected vars = ";
                    print STDERR &Dumper ($test->{evars});
                    printf STDERR "What we got = ";
                    print STDERR &Dumper ($vars);
                }
            }

            # Now substitute.
            foreach my $var (@$vars) {
                my $name = $var->{name};
                my $replacement = $values->{$name};
                my $vref = $var->{vref};
                #print "OLD VARIABLE '$name' => " . &Dumper ($$vref) . "\n";
                $$vref = $replacement;
                #print "NEW VARIABLE '$name' => " . &Dumper ($replacement) . "\n";
            }

            $ntests++;
            if (!ok (&Compare ($test->{after}, $result), "TEST ($test->{name}) After")) {
                printf STDERR "Result does not match, expected vars = ";
                print STDERR &Dumper ($test->{after});
                printf STDERR "What we got = ";
                print STDERR &Dumper ($result);
            }
        }
    }
    # print "EXPECTED KEYS\n";
    # foreach my $key (sort (keys %{ $test->{expected} })) {
    #     print ">> KEY '$key' " . (utf8::is_utf8 ($key) ? "IS UTF-8" : "not") . "\n";
    # }

    # print "ACTUAL KEYS\n";
    # foreach my $key (sort (keys %$result)) {
    #     print ">> KEY '$key' " . (utf8::is_utf8 ($key) ? "IS UTF-8" : "not") . "\n";
    # }

    #utf8::is_utf8 ($result) and print STDERR "String is UTF-8.\n";
    #$result and print &Dumper ($result);
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