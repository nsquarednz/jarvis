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
use JSON::PP;

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

###############################################################################
# Select all three ships (name only) - projection test.
###############################################################################

my $olympic_id = $json->{row}[0]{returning}[0]{_id};
my $queen_mary_id = $json->{row}[1]{returning}[0]{_id};
my $titanic_id = $json->{row}[2]{returning}[0]{_id};

my $expected = [
    {
        'name' => 'Olympic',
        '_id' => $olympic_id,
        num_funnels => undef,
    },
    {
        'name' => 'Queen Mary',
        '_id' => $queen_mary_id,
    },
    {
        'name' => 'Titanic',
        '_id' => $titanic_id,
        'num_funnels' => 4,
    }
];

$json = TestUtils::fetch_json ([ 'ship_project' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships (ship_project)")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

if (! eq_or_diff ($json->{data}, $expected, 'New Rows after Insert (ship_project) matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Select all three ships, all fields.
###############################################################################

$$expected[0]{line} = 'White Star';
$$expected[1]{line} = 'Cunard';
$$expected[2]{line} = 'White Star';

$json = TestUtils::fetch_json ([ 'ship' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships (ship)")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

if (! eq_or_diff ($json->{data}, $expected, 'New Rows after Insert (ship) matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Update the number of funnels on the Queen Mary.
###############################################################################

# Give the Queen Mary 7 funnels.
my $update_ships = [ { '_id' => $queen_mary_id, num_funnels => 7  } ];

$json = TestUtils::store ([ 'ship' ], { _method => 'update' }, $update_ships);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Update Queen Mary")) {
    BAIL_OUT("Failed to update: " . &Dumper ($json));    
}

$$expected[1]{num_funnels} = 7;

$json = TestUtils::fetch_json ([ 'ship' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships (ship)")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

if (! eq_or_diff ($json->{data}, $expected, 'Updated Rows after Update Queen Mary matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Delete (but not really) the Olympic.
###############################################################################

# Give the Queen Mary 7 funnels.
my $deactivate_ships = [ { '_id' => $olympic_id } ];

$json = TestUtils::store ([ 'ship_deactivate' ], { _method => 'delete' }, $deactivate_ships);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Deactivate Queen Mary")) {
    BAIL_OUT("Failed to update: " . &Dumper ($json));    
}

$$expected[0]{deleted} = JSON::PP::true;

$json = TestUtils::fetch_json ([ 'ship' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships (ship)")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

if (! eq_or_diff ($json->{data}, $expected, 'Updated Rows after Update Queen Mary matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Select all three ships, all fields.  With Paging.
###############################################################################

shift (@$expected);
shift (@$expected);

$json = TestUtils::fetch_json ([ 'ship' ], { limit => 2, start => 2 });
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Ships (ship)")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

if (! eq_or_diff ($json->{data}, $expected, 'New Rows after Insert (ship) matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

done_testing ();
