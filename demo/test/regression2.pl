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
$json = TestUtils::fetch_json ([ 'ship_project' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

# Now delete them all.
if (scalar @{ $json->{data} }) {    
    my @delete = map { { _id => $_->{_id} }; } @{ $json->{data} };
    $json = TestUtils::store ([ 'ship' ], { _method => 'delete' }, \@delete);
    if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} >= 1), "JSON Delete all Ships")) {
        BAIL_OUT("Failed to delete: " . &Dumper ($json));    
    }
}

###############################################################################
# Insert Three Ships
###############################################################################

my $new_ships = [
    { name => 'Olympic', line => 'White Star', num_funnels => undef },
    { name => 'Queen Mary', line => 'Cunard' },
    { name => 'Titanic', line => 'White Star', num_funnels => 4, dummy => 'IGNORED' },
];

$json = TestUtils::store ([ 'ship' ], { _method => 'insert' }, $new_ships);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 3), "JSON Insert new Ships")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));    
}

my $expected = [
    {
        'name' => 'Olympic',
        '_id' => $json->{row}[0]{returning}[0]{_id},
    },
    {
        'name' => 'Queen Mary',
        '_id' => $json->{row}[1]{returning}[0]{_id},
    },
    {
        'name' => 'Titanic',
        '_id' => $json->{row}[2]{returning}[0]{_id}
    }
];

$json = TestUtils::fetch_json ([ 'ship_project' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

if (! eq_or_diff ($json->{data}, $expected, 'New Rows after Insert matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

# $expected = [
#     {
#         'success' => 1,
#         'modified' => '1',
#         'returning' => [
#             {
#                 'name' => 'Fatal Dodger',
#                 'class' => 'Makkleson',
#                 'id' => $fd_boat_id
#             }
#         ]
#     }
# ];


done_testing ();
