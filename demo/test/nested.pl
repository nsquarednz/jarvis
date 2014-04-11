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
my @all_boats = @{ $json->{data} };

###############################################################################
# Delete/Create Boat "Empty Nest"
###############################################################################
my $en_boat_name = 'Empty Nest';
my $en_boat_class = 'X Class';
my @my_boat = grep { $_->{name} eq $en_boat_name } @all_boats;
if (scalar @my_boat) {
	my $id = $my_boat[0]->{id};
	print "TEST: Deleting Boat '$en_boat_name' (ID $id)\n";
	my $delete = [
		{ id => $id }
	];
	$json = TestUtils::store ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1))) {
	    BAIL_OUT("Failed to store: " . &Dumper ($json));    
	}
}

print "TEST: Inserting Boat '$en_boat_name'\n";
my $insert = [
	{ name => $en_boat_name, class => $en_boat_class }
];
$json = TestUtils::store ([ 'boat' ], { _method => 'insert' }, $insert);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1))) {
    BAIL_OUT("Failed to store: " . &Dumper ($json));    
}
my $en_boat_id = $json->{row}[0]{returning}[0]{id};
print ">>> New Boat '$en_boat_name' (ID $en_boat_id)\n";

###############################################################################
# Delete/Create Boat "Fatal Dodger"
###############################################################################
my $fd_boat_name = 'Fatal Dodger';
my $fd_boat_class = 'Makkleson';
@my_boat = grep { $_->{name} eq $fd_boat_name } @all_boats;
if (scalar @my_boat) {
	my $id = $my_boat[0]->{id};
	print "TEST: Deleting Boat '$fd_boat_name' (ID $id)\n";
	my $delete = [
		{ id => $id }
	];
	$json = TestUtils::store ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1))) {
	    BAIL_OUT("Failed to store: " . &Dumper ($json));    
	}
}

print "TEST: Inserting Boat '$fd_boat_name'\n";
$insert = [
	{ name => $fd_boat_name, class => $fd_boat_class }
];
$json = TestUtils::store ([ 'boat' ], { _method => 'insert' }, $insert);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1))) {
    BAIL_OUT("Failed to store: " . &Dumper ($json));    
}
my $fd_boat_id = $json->{row}[0]{returning}[0]{id};
print ">>> New Boat '$fd_boat_name' (ID $fd_boat_id)\n";

###############################################################################
# Add parts to "Empty Nest"
###############################################################################
print "TEST: Inserting Boat Parts for '$en_boat_name'\n";
$insert = [
	{ boat_id => $en_boat_id, name => "Widget" },
	{ boat_id => $en_boat_id, name => "Sprocket" },
	{ boat_id => $en_boat_id, name => "Gadget" },
];
$json = TestUtils::store ([ 'boat_part' ], { _method => 'insert' }, $insert);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 3))) {
    BAIL_OUT("Failed to store: " . &Dumper ($json));    
}
my @part_ids = map { $_->{returning}[0]{id} } @{ $json->{row} };

###############################################################################
# OK, now try a nested fetch!
###############################################################################
print "TEST: Selecting Nested Boat Object for '$en_boat_name'\n";
$json = TestUtils::fetch ([ 'boat_object' ], { id => $en_boat_id });

if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data})) {
    BAIL_OUT("Failed to store: " . &Dumper ($json));    
}
print &Dumper ($json);

done_testing ();