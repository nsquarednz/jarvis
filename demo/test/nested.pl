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

###############################################################################
# Initial Set-Up
#	- Test logout
#	- Test login - logged_in
#	- Test login - group_list
#	- Test GLOBAL return_status () hook - $hook_params_href
#	- Test GLOBAL return_status () hook - $extra_href
###############################################################################

# Logout.
my $json = TestUtils::logout ();
if (! ok ($json->{logged_in} == 0, "Log Out")) {
    BAIL_OUT("Failed to logout: " . &Dumper ($json));    
}

# Login.
$json = TestUtils::login ("admin");
if (! ok ($json->{logged_in} == 1, "Log In")) {
    BAIL_OUT("Failed to login: " . &Dumper ($json));    
}
if (! eq_or_diff ($json->{quota}, "4 Gazillion", '__status quota parameter matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($json));    
}
if (! eq_or_diff ($json->{group_list}, "admin,default", '__status group_list matches.')) {
    BAIL_OUT("Unexpected __status group_list: " . &Dumper ($json));    
}

# Get all boats.
$json = TestUtils::fetch_json ([ 'boat' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "Get all Boats")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}
if (! eq_or_diff ($json->{quota}, "4 Gazillion", '__status quota parameter matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($json));    
}
my @all_boats = @{ $json->{data} };

###############################################################################
# Delete/Create Boat "Empty Nest"
#	- Test Single Row non-nested delete
#	- Test Single Row non-nested insert
###############################################################################
my $en_boat_name = 'Empty Nest';
my $en_boat_class = 'X Class';
my @my_boat = grep { $_->{name} eq $en_boat_name } @all_boats;
if (scalar @my_boat) {
	my $id = $my_boat[0]->{id};
	my $delete = [
		{ id => $id }
	];
	$json = TestUtils::store ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "Delete Boat '$en_boat_name'")) {
	    BAIL_OUT("Failed to delete: " . &Dumper ($json));    
	}
}

my $insert = [
	{ name => $en_boat_name, class => $en_boat_class }
];
$json = TestUtils::store ([ 'boat' ], { _method => 'insert' }, $insert);
my $en_boat_id = $json->{row}[0]{returning}[0]{id};
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1) && $en_boat_id, "Insert Boat '$en_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));    
}

###############################################################################
# Fetch Boat "Empty Nest" by ID as a Singleton
#	- Test <router> named parameter "id" for dataset
#	- Test <router> singleton
###############################################################################

$json = TestUtils::fetch_json ([ 'boat_singleton', $en_boat_id ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "Get Boat '$en_boat_name' by ID $en_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}
my $expected = {
    'owner' => '',
    'registration_num' => '',
    'name' => 'Empty Nest',
    'class' => 'X Class',
    'id' => $en_boat_id,
    'description' => ''
};
if (! eq_or_diff ($json->{data}, $expected, 'Singleton Fetch matches.')) {
    BAIL_OUT("Unexpected Singleton Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Fetch Boat "Empty Nest" by ID (array)
#	- Test GLOBAL hook access to $rows_aref
#	- Test <router> array
###############################################################################

$json = TestUtils::fetch_json ([ 'boat', $en_boat_id ], { duplicate => 1 });
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "Get Boat '$en_boat_name' by ID $en_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}
$expected = [ {
    'owner' => '',
    'registration_num' => '',
    'name' => 'Empty Nest',
    'class' => 'X Class',
    'id' => $en_boat_id,
    'description' => ''
}, {
    'owner' => '',
    'registration_num' => '',
    'name' => 'Empty Nest',
    'class' => 'X Class',
    'id' => $en_boat_id,
    'description' => ''
} ];
if (! eq_or_diff ($json->{data}, $expected, 'Duplicated Fetch matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Delete/Create Boat "Fatal Dodger"
#	- Test Single Row non-nested delete
#	- Test Single Row non-nested insert
###############################################################################
my $fd_boat_name = 'Fatal Dodger';
my $fd_boat_class = 'Makkleson';
@my_boat = grep { $_->{name} eq $fd_boat_name } @all_boats;
if (scalar @my_boat) {
	my $id = $my_boat[0]->{id};
	my $delete = [
		{ id => $id }
	];
	$json = TestUtils::store ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "Delete Boat '$fd_boat_name'")) {
	    BAIL_OUT("Failed to delete: " . &Dumper ($json));    
	}
}

$insert = [
	{ name => $fd_boat_name, class => $fd_boat_class }
];
$json = TestUtils::store ([ 'boat' ], { _method => 'insert' }, $insert);
my $fd_boat_id = $json->{row}[0]{returning}[0]{id};
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1) && $fd_boat_id, "Insert Boat '$fd_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));    
}

$expected = [
	{
		'success' => 1,
		'modified' => '1',
		'returning' => [
			{
				'name' => 'Fatal Dodger',
				'class' => 'Makkleson',
				'id' => $fd_boat_id
			}
		]
	}
];
if (! eq_or_diff ($json->{row}, $expected, "Insert Boat '$fd_boat_name' Returned Row Check")) {
    BAIL_OUT("Unexpected insert result: " . &Dumper ($json));    
}

###############################################################################
# Add parts to "Empty Nest"
###############################################################################
$insert = [
	{ boat_id => $en_boat_id, name => "Widget" },
	{ boat_id => $en_boat_id, name => "Sprocket" },
	{ boat_id => $en_boat_id, name => "Gadget" },
];
$json = TestUtils::store ([ 'boat_part' ], { _method => 'insert' }, $insert);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 3), "Insert Boat Parts for '$en_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));    
}
my @part_ids = map { $_->{returning}[0]{id} } @{ $json->{row} };

###############################################################################
# OK, now try a nested fetch!
###############################################################################
$json = TestUtils::fetch_json ([ 'boat_object' ], { id => $en_boat_id });

if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "Select Nested Boat Object for '$en_boat_name'")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}

###############################################################################
# Delete/Insert NESTED "Mother Hubbard" with many children.
###############################################################################
my $mh_boat_name = 'Mother Hubbard';
my $mh_boat_class = 'X Class';

@my_boat = grep { $_->{name} eq $mh_boat_name } @all_boats;
if (scalar @my_boat) {
	$json = TestUtils::store ([ 'boat' ], { _method => 'delete' }, [ { id => $my_boat[0]->{id} } ]);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "Delete Boat '$mh_boat_name'")) {
	    BAIL_OUT("Failed to delete: " . &Dumper ($json));    
	}
}

$insert = [
	{ 
		name => $mh_boat_name, 
		class => $mh_boat_class, 
	  	parts => [
			{ name => "Doodad" },
			{ name => "Whatsit" },
			{ name => "Hoosit" },
		]
	}
];
$json = TestUtils::store ([ 'boat_object' ], { _method => 'insert' }, $insert);
my $mh_boat_id = $json->{row}[0]{returning}[0]{id};
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1) && $mh_boat_id, "Nested Insert for '$mh_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));    
}
my $mh_doodad_id = $json->{row}[0]{child}{parts}{row}[0]{returning}[0]{id};
my $mh_whatsit_id = $json->{row}[0]{child}{parts}{row}[1]{returning}[0]{id};
my $mh_hoosit_id = $json->{row}[0]{child}{parts}{row}[2]{returning}[0]{id};

###############################################################################
# Nested Update: Change Class, delete Doodad, and Thingey.
###############################################################################
my $update = [
	{ 
		_ttype => 'update',
		id => $mh_boat_id,
		name => $mh_boat_name, 
		class => 'Makkleson', 
	  	parts => [
			{ _ttype => 'delete', id => $mh_doodad_id,  },
			{ _ttype => 'update', id => $mh_whatsit_id, name => "Whatsitt" },
			{ _ttype => 'insert', name => "Thingey" },
		]
	}
];
$json = TestUtils::store ([ 'boat_object' ], { _method => 'mixed' }, $update);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "Nested Update for '$mh_boat_name'")) {
    BAIL_OUT("Failed to mixed: " . &Dumper ($json));    
}
my $mh_thingey_id = $json->{row}[0]{child}{parts}{row}[2]{returning}[0]{id};

###############################################################################
# Re-Fetch Boat "Mother Hubbard" Object by ID (singleton)
#	- Test previous Nested Insert/Update correctness.
###############################################################################

$json = TestUtils::fetch_json ([ 'boat_object', $mh_boat_id ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "Get Boat '$mh_boat_name' by ID $mh_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));    
}
$expected = {
    'owner' => '',
    'registration_num' => '',
    'name' => $mh_boat_name,
    'class' => 'Makkleson',
    'id' => $mh_boat_id,
    'description' => '',
    'parts' => [
    	{ 'name' => 'Hoosit', 'id' => $mh_hoosit_id },
    	{ 'name' => 'Thingey', 'id' => $mh_thingey_id },
    	{ 'name' => 'Whatsitt', 'id' => $mh_whatsit_id },
    ]
};
if (! eq_or_diff ($json->{data}, $expected, 'Duplicated Fetch matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));    
}

###############################################################################
# Invoke the File-Download Plugin
#	- Test <router> named parameter "boat_class" for plugin
#	- Test plugin - $user_args args
#	- Test plugin - %plugin_args
###############################################################################

my $x_boat_class = 'X Class';
my $content = TestUtils::fetch ([ 'file_download', $x_boat_class ]);

$expected = "Param|Value
App Name|demo
Interview|Cross-Sectional
Rest 0|file_download
Rest 1|X Class
Boat Class|X Class
All Boats|4";

if (! eq_or_diff ($content, $expected, 'FileDownload Plugin Content Check')) {
    BAIL_OUT("Unexpected FilePlugin result: " . &Dumper ($content));    
}

done_testing ();
