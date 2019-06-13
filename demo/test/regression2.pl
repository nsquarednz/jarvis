#!/usr/bin/perl
#
# Regression test suite Part 2 -- MongoDB.
#
use strict;
use warnings;

use lib "./lib";

use Test::More;
use Test::Differences;
use Data::Dumper;

use TestUtils;

###############################################################################
# Initial Set-Up
#   - Test logout
#   - Test login - logged_in
###############################################################################

# Logout.
my $json = TestUtils::logout_json ();
if (! ok ($json->{logged_in} == 0, "JSON Log Out")) {
    BAIL_OUT("Failed to logout: " . &Dumper ($json));    
}

# Login.
$json = TestUtils::login_json ("admin");
if (! ok ($json->{logged_in} == 1, "JSON Log In")) {
    BAIL_OUT("Failed to login: " . &Dumper ($json));    
}

###############################################################################
# Fetch All and Delete All (to get to empty DB)
###############################################################################

# Get all boats.
$json = TestUtils::fetch_json ([ 'ship' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}
my @all_ships = @{ $json->{data} };


if (scalar @all_ships) {    
    my @delete = map { { _id => $_->{_id} }; } @all_ships;
    #die &Dumper (\@delete);
    $json = TestUtils::store ([ 'ship' ], { _method => 'delete' }, \@delete);
    if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Delete all Ships")) {
        BAIL_OUT("Failed to delete: " . &Dumper ($json));    
    }
}


done_testing ();
