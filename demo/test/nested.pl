#!/usr/bin/perl
#
# Nested Dataset unit tests against demo app database.
#
use strict;
use warnings;

use lib "./lib";

use Test::More;
use Test::Differences;
use Data::Dumper;
use Data::Hexdumper;
use Data::Compare;

use TestUtils;

# Logout.
print "TEST: Logout\n";
my $json = TestUtils::logout ();
if (! ok ($json->{logged_in} == 0)) {
    BAIL_OUT("Failed to logout: " . &Dumper ($json));    
}

# Login.
print "TEST: Login\n";
$json = TestUtils::login ("admin");
if (! ok ($json->{logged_in} == 1)) {
    BAIL_OUT("Failed to login: " . &Dumper ($json));    
}

# Get all boats.
print "TEST: Get all Boats\n";
$json = TestUtils::fetch ([ 'boat' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data})) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

# Delete any boat named "Empty Nest".
my $boat_name = 'Empty Nest';
my $boat_class = 'X Class';
my @boats = grep { $_->{name} eq $boat_name } @{ $json->{data} };
if (scalar @boats) {
	my $id = $boats[0]->{id};
	print "TEST: Deleting Boat '$boat_name' (ID $id)\n";
	my $delete = [
		{ id => $id }
	];
	$json = TestUtils::store ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1))) {
	    BAIL_OUT("Failed to store: " . &Dumper ($json));    
	}
}

# Insert a boat named "Empty Nest";
print "TEST: Inserting Boat '$boat_name'\n";
my $insert = [
	{ name => $boat_name, class => $boat_class }
];
$json = TestUtils::store ([ 'boat' ], { _method => 'insert' }, $insert);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1))) {
    BAIL_OUT("Failed to store: " . &Dumper ($json));    
}
my $boat_id = $json->{row}[0]{returning}[0]{id};
print "    : New Boat (ID $boat_id)\n";


done_testing ();