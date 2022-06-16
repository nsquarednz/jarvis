#!/usr/bin/perl
#
# Regression test suite Part 1 -- exec and DBI.
#
use strict;
use warnings;

use lib "./lib";

use B qw( svref_2object SVf_IOK );
use Test::More;
use Test::Differences;
use Data::Dumper;
use Getopt::Long;

use TestUtils;

################################################################################
# Flags.
################################################################################
my $base_url_override = undef;
&Getopt::Long::GetOptions ("base_url_override=s" => \$base_url_override) || die "usage: perl $0 [--base_url_override <override_uri>]";
if ($base_url_override) {
    $TestUtils::base_url = $base_url_override;
}

###############################################################################
# Initial Set-Up
#	- Test logout
#	- Test login - logged_in
#	- Test login - group_list
#	- Test GLOBAL return_status () hook - $hook_params_href
#	- Test GLOBAL return_status () hook - $extra_href
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
if (! eq_or_diff ($json->{quota}, "4 Gazillion", 'JSON Login quota parameter matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($json));
}
if (! eq_or_diff ($json->{sideband}, "Special Include", 'JSON Login sideband parameter matches.')) {
    BAIL_OUT("Unexpected __status sideband: " . &Dumper ($json));
}
if (! eq_or_diff ($json->{group_list}, "admin,default", 'JSON Login group_list matches.')) {
    BAIL_OUT("Unexpected __status group_list: " . &Dumper ($json));
}

# JSON Status check
$json = TestUtils::fetch_json ([ '__status' ]);
if (! ok (defined $json->{logged_in} && $json->{logged_in}, "JSON Status")) {
    BAIL_OUT("Failed to JSON status: " . &Dumper ($json));
}

# XML Status check
my $xml = TestUtils::fetch_xml ([ '__status' ]);
if (! ok (defined $xml->{response} && defined $xml->{response}{logged_in} && $xml->{response}{logged_in}->content, "XML Status")) {
    BAIL_OUT("Failed to XML status: " . &Dumper ($xml));
}

###############################################################################
# ECHO
###############################################################################

my $text = TestUtils::fetch ([ 'echo' ], { paramA => 'a', paramB => 'b' }, 'text/plain');
if (! ok (defined $text, "Echo")) {
    BAIL_OUT("Failed to echo: " . &Dumper ($text));
}
if (! eq_or_diff ($text, "p0=echo __LIMIT=2 __dataset=echo __group:admin=1 __group:default=1 __group_list=admin,default __username=admin max_rows=500 paramA=a paramB=b\n", 'Echo matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($text));
}

$text = TestUtils::fetch ([ 'echo2' ], { paramA => 'A', paramB => 'B' }, 'text/plain');
if (! ok (defined $text, "Echo2")) {
    BAIL_OUT("Failed to echo2: " . &Dumper ($text));
}
if (! eq_or_diff ($text, "p0=echo2 __LIMIT=2 __dataset=echo2 __group:admin=1 __group:default=1 __group_list=admin,default __username=admin max_rows=500 paramA=A paramB=B\n", 'Echo matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($text));
}

###############################################################################
# Simple Fetch
###############################################################################

# Get all boats.
$json = TestUtils::fetch_json ([ 'boat' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get all Boats")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}
if (! eq_or_diff ($json->{quota}, "4 Gazillion", 'JSON Fetch quota parameter matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($json));
}
my @all_boats = @{ $json->{data} };

# Repeat for XML format.
$xml = TestUtils::fetch_xml ([ 'boat' ]);
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get all Boats")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}
if (! eq_or_diff ($xml->{response}{quota}->content, "4 Gazillion", 'XML Fetch quota parameter matches.')) {
    BAIL_OUT("Unexpected __status quota: " . &Dumper ($xml));
}

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
	$json = TestUtils::store_json ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Delete Boat '$en_boat_name'")) {
	    BAIL_OUT("Failed to delete: " . &Dumper ($json));
	}
}

my $insert = [
	{ name => $en_boat_name, class => $en_boat_class }
];
$json = TestUtils::store_json ([ 'boat' ], { _method => 'insert' }, $insert);
my $en_boat_id = $json->{row}[0]{returning}[0]{id};
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1) && $en_boat_id, "JSON Insert Boat '$en_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));
}

###############################################################################
# Duplicate INSERT!
###############################################################################

my ($code, $message) = TestUtils::store_json ([ 'boat' ], { _method => 'insert' }, $insert, 1);

# Note when running under FastCGI we will get back a message that looks something like:
# [Thu Mar  4 01:58:19 2021] fast-agent.fcgi: UNIQUE constraint failed: boat.name
# We should regex match looking for the latter part of the string.
if (! ok (($code == 409) && ($message =~ /^.*UNIQUE constraint failed: boat\.name\n$/gm), "JSON Insert Boat '$en_boat_name' Duplicate")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($code, $message));
}

###############################################################################
# Fetch Boat "Empty Nest" by ID as a Singleton
#	- Test <router> named parameter "id" for dataset
#	- Test <router> singleton
###############################################################################

$json = TestUtils::fetch_json ([ 'boat_singleton', $en_boat_id ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get Boat Singleton '$en_boat_name' by ID $en_boat_id")) {
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
if (! eq_or_diff ($json->{data}, $expected, 'JSON Singleton Fetch matches.')) {
    BAIL_OUT("Unexpected Singleton Fetch result: " . &Dumper ($json));
}

# Repeat for XML format.
$xml = TestUtils::fetch_xml ([ 'boat_singleton', $en_boat_id ]);
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get Boat Singleton '$en_boat_name' by ID $en_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}
my $row0 = $xml->{response}{data}{row}[0];
if (! ok (($row0->{owner}->content eq '') &&
		  ($row0->{registration_num}->content eq '') &&
		  ($row0->{name}->content eq 'Empty Nest') &&
		  ($row0->{class}->content eq 'X Class') &&
		  ($row0->{id}->content eq $en_boat_id) &&
		  ($row0->{description}->content eq ''),
		  'XML Singleton Fetch matches.')) {

    BAIL_OUT("Unexpected Singleton Fetch result: " . &Dumper ($xml));
}

###############################################################################
# Fetch Boat "Empty Nest" by ID (array)
#	- Test GLOBAL hook access to $rows_aref
#	- Test <router> array
###############################################################################

$json = TestUtils::fetch_json ([ 'boat', $en_boat_id ], { duplicate => 1 });
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get Boat '$en_boat_name' by ID $en_boat_id with Duplicate")) {
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

# Check the ID is actually an integer.
my $sv = svref_2object (\$json->{data}[0]{id});
if (! ok ($sv->FLAGS & SVf_IOK, "Fetched boat[0].id is IV.")) {
    BAIL_OUT("Fetched boat[0].id is not IV: " . &Dumper ($json));
}

if (! eq_or_diff ($json->{data}, $expected, 'JSON Duplicated Fetch matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));
}

# Repeat for XML format.
$xml = TestUtils::fetch_xml ([ 'boat', $en_boat_id ], { duplicate => 1 });
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get Boat '$en_boat_name' by ID $en_boat_id with Duplicate")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}

# Its a bit fiddly but I just don't know how else to get an array of objects from a response.
# Process each node.
my @nodes = $xml->{response}{data}->nodes;
my $parsed_content;
foreach my $node (@nodes) {
    # Get all the arg value objects.
    my @arg_values = map $_->args_values, $node;
    my $content;
    # Map each arg value object key and content to a hash.
    map $content->{$_->key} = $_->content, @arg_values;
    push @{$parsed_content}, $content;
}

if (! eq_or_diff ($parsed_content, $expected, 'XML Duplicated Fetch matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($xml));
}

###############################################################################
# Get all boats and test paging.
###############################################################################

$json = TestUtils::fetch_json ([ 'boat' ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get All Boats")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}

my $num_rows = scalar (@{ $json->{data} });
if (! ok ($num_rows > 10, 'JSON All Boats Fetch count.')) {
    BAIL_OUT("Unexpected All Boats Fetch count: " . &Dumper ($json));
}

# Repeat for XML format.
$xml = TestUtils::fetch_xml ([ 'boat' ]);
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get All Boats")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}

$num_rows = scalar ($xml->{response}{data}->nodes);
if (! ok ($num_rows > 10, 'XML All Boats Fetch count.')) {
    BAIL_OUT("Unexpected All Boats Fetch count: " . &Dumper ($xml));
}

# NOTE: "start" and "limit" parameter names are specified in demo.xml
#
# Test page 1 counts.
$json = TestUtils::fetch_json ([ 'boat' ], { start => 0, limit => 5 });
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get All Boats Page 1")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}
if (! ok (($json->{returned} == 5) && ($json->{fetched} == $num_rows), "JSON Page 1 Sizing")) {
    BAIL_OUT("Page 1 Sizing: ". &Dumper ($json));
}
my $page1_name = $json->{data}[0]{name};

# Test page 2 counts.
$json = TestUtils::fetch_json ([ 'boat' ], { start => 5, limit => 5 });
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get All Boats Page 2")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}
if (! ok (($json->{returned} == 5) && ($json->{fetched} == $num_rows), "JSON Page 2 Sizing")) {
    BAIL_OUT("Page 2 Sizing: ". &Dumper ($json));
}
my $page2_name = $json->{data}[0]{name};

if (! ok ($page1_name ne $page2_name, "JSON Page 1 and Page 2 Differ")) {
    BAIL_OUT("Page 1 ($page1_name) eq Page 2 ($page2_name)");
}


# Repeat Page Tests in XML
$xml = TestUtils::fetch_xml ([ 'boat' ], { start => 0, limit => 5 });
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get All Boats Page 1")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}
if (! ok (($xml->{response}{returned} == 5) && ($xml->{response}{fetched} == $num_rows), "XML Page 1 Sizing")) {
    BAIL_OUT("Page 1 Sizing: ". &Dumper ($xml));
}
$page1_name = $xml->{response}{data}{row}[0]{name}->content;

# Test page 2 counts.
$xml = TestUtils::fetch_xml ([ 'boat' ], { start => 5, limit => 5 });
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get All Boats Page 2")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}
if (! ok (($xml->{response}{returned} == 5) && ($xml->{response}{fetched} == $num_rows), "XML Page 2 Sizing")) {
    BAIL_OUT("Page 2 Sizing: ". &Dumper ($xml));
}
$page2_name = $xml->{response}{data}{row}[0]{name}->content;

if (! ok ($page1_name ne $page2_name, "XML Page 1 and Page 2 Differ")) {
    BAIL_OUT("Page 1 ($page1_name) eq Page 2 ($page2_name)");
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
	$json = TestUtils::store_json ([ 'boat' ], { _method => 'delete' }, $delete);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Delete Boat '$fd_boat_name'")) {
	    BAIL_OUT("Failed to delete: " . &Dumper ($json));
	}
}

$insert = [
	{ name => $fd_boat_name, class => $fd_boat_class }
];
$json = TestUtils::store_json ([ 'boat' ], { _method => 'insert' }, $insert);
my $fd_boat_id = $json->{row}[0]{returning}[0]{id};
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1) && $fd_boat_id, "JSON Insert Boat '$fd_boat_name'")) {
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
# Merge, changing name and registration only.
###############################################################################
my $update = [
    {
        id => $fd_boat_id,
        class => 'X Class',
        registration_num => 47
    }
];
$json = TestUtils::store_json ([ 'boat' ], { _method => 'merge' }, $update);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Merge (class/registration_num) for '$fd_boat_name'")) {
    BAIL_OUT("Failed to merge: " . &Dumper ($json));
}

# Validate:
$json = TestUtils::fetch_json ([ 'boat' ], { id => $fd_boat_id });
if (! ok (defined $json->{returned} && defined $json->{fetched} && ($json->{fetched} == 1), "JSON Get Fatal Dodger $fd_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}
$expected = {
    'id' => $fd_boat_id,
    'name' => $fd_boat_name,
    'class' => 'X Class',
    'owner' => '',
    'registration_num' => 47,
    'description' => '',
};
if (! eq_or_diff ($json->{data}[0], $expected, 'JSON Object Fetch matches.')) {
    BAIL_OUT("Unexpected Merge (class/registration_num) Fetch result: " . &Dumper ($json));
}

###############################################################################
# This time merge the description and remove the registration_num.
###############################################################################
$update = [
    {
        id => $fd_boat_id,
        description => 'Slightly Scruffy',
        registration_num => undef
    }
];
$json = TestUtils::store_json ([ 'boat' ], { _method => 'merge' }, $update);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Merge (description/registration_num) for '$fd_boat_name'")) {
    BAIL_OUT("Failed to merge: " . &Dumper ($json));
}

# Validate:
$json = TestUtils::fetch_json ([ 'boat' ], { id => $fd_boat_id });
if (! ok (defined $json->{returned} && defined $json->{fetched} && ($json->{fetched} == 1), "JSON Get Fatal Dodger $fd_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}
$expected = {
    'id' => $fd_boat_id,
    'name' => $fd_boat_name,
    'class' => 'X Class',
    'owner' => '',
    'registration_num' => '',
    'description' => 'Slightly Scruffy',
};
if (! eq_or_diff ($json->{data}[0], $expected, 'JSON Object Fetch matches.')) {
    BAIL_OUT("Unexpected Merge (description/registration_num) Fetch result: " . &Dumper ($json));
}

###############################################################################
# Add parts to "Empty Nest"
###############################################################################
$insert = [
	{ boat_id => $en_boat_id, name => "Widget" },
	{ boat_id => $en_boat_id, name => "Sprocket" },
	{ boat_id => $en_boat_id, name => "Gadget" },
];
$json = TestUtils::store_json ([ 'boat_part' ], { _method => 'insert' }, $insert);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 3), "JSON Insert Boat Parts for '$en_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));
}
my @part_ids = map { $_->{returning}[0]{id} } @{ $json->{row} };

###############################################################################
# OK, now try a nested fetch!
###############################################################################
$json = TestUtils::fetch_json ([ 'boat_object' ], { id => $en_boat_id });
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Select Nested Boat Object for '$en_boat_name'")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}

# Repeat for XML.
$xml = TestUtils::fetch_xml ([ 'boat_object' ], { id => $en_boat_id });
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "JSON Select Nested Boat Object for '$en_boat_name'")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}

###############################################################################
# Delete/Insert NESTED "Mother Hubbard" with many children.
###############################################################################
my $mh_boat_name = 'Mother Hubbard';
my $mh_boat_class = 'X Class';

@my_boat = grep { $_->{name} eq $mh_boat_name } @all_boats;
if (scalar @my_boat) {
	$json = TestUtils::store_json ([ 'boat' ], { _method => 'delete' }, [ { id => $my_boat[0]->{id} } ]);
	if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Delete Boat '$mh_boat_name'")) {
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
$json = TestUtils::store_json ([ 'boat_object' ], { _method => 'insert' }, $insert);
my $mh_boat_id = $json->{row}[0]{returning}[0]{id};
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1) && $mh_boat_id, "JSON Nested Insert for '$mh_boat_name'")) {
    BAIL_OUT("Failed to insert: " . &Dumper ($json));
}
my $mh_doodad_id = $json->{row}[0]{child}{parts}{row}[0]{returning}[0]{id};
my $mh_whatsit_id = $json->{row}[0]{child}{parts}{row}[1]{returning}[0]{id};
my $mh_hoosit_id = $json->{row}[0]{child}{parts}{row}[2]{returning}[0]{id};

###############################################################################
# Nested Update: Change Class, delete Doodad, and Thingey.
###############################################################################
$update = [
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
$json = TestUtils::store_json ([ 'boat_object' ], { _method => 'mixed' }, $update);
if (! ok (defined $json->{success} && defined $json->{modified} && ($json->{success} == 1) && ($json->{modified} == 1), "JSON Nested Update for '$mh_boat_name'")) {
    BAIL_OUT("Failed to mixed: " . &Dumper ($json));
}
my $mh_thingey_id = $json->{row}[0]{child}{parts}{row}[2]{returning}[0]{id};

# Lets also try and do an update via XML.
my $xml_update = [
    {
        _ttype => 'update',
        id => $mh_boat_id,
        name => $mh_boat_name,
        class => 'Makkleson'
    }
];

#
# This generates:
# <?xml version="1.0" encoding="iso-8859-1" ?>
# <?meta name="GENERATOR" content="XML::Smart/1.78 Perl/5.026001 [linux]" ?>
# <request _ttype="update" class="Makkleson" id="299" name="Mother Hubbard"/>
#
$xml = TestUtils::store_xml ([ 'boat_object' ], { _method => 'mixed' }, $xml_update);
if (! ok (defined $xml->{response}{success} && defined $xml->{response}{modified} && ($xml->{response}{success}->content == 1) && ($xml->{response}{modified}->content == 1), "XML Nested Update for '$mh_boat_name'")) {
    BAIL_OUT("Failed to mixed: " . &Dumper ($xml));
}

###############################################################################
# Re-Fetch Boat "Mother Hubbard" Object by ID (singleton)
#	- Test previous Nested Insert/Update correctness.
###############################################################################

$json = TestUtils::fetch_json ([ 'boat_object', $mh_boat_id ]);
if (! ok (defined $json->{returned} && defined $json->{fetched} && defined $json->{data}, "JSON Get Boat '$mh_boat_name' by ID $mh_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($json));
}
$expected = {
    'owner' => '',
    'registration_num' => '',
    'name' => $mh_boat_name,
    'class' => 'Makkleson',
    'id' => $mh_boat_id,
    'description' => '',
    'foo' => 'Foo',
    'parts' => [
    	{ 'name' => 'Hoosit', 'id' => $mh_hoosit_id, 'bar' => 'Bar' },
    	{ 'name' => 'Thingey', 'id' => $mh_thingey_id, 'bar' => 'Bar' },
    	{ 'name' => 'Whatsitt', 'id' => $mh_whatsit_id, 'bar' => 'Bar' },
    ]
};
if (! eq_or_diff ($json->{data}, $expected, 'JSON Object Fetch matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($json));
}

$xml = TestUtils::fetch_xml ([ 'boat_object', $mh_boat_id ]);
if (! ok (defined $xml->{response}{returned} && defined $xml->{response}{fetched} && defined $xml->{response}{data}, "XML Get Boat '$mh_boat_name' by ID $mh_boat_id")) {
    BAIL_OUT("Failed to fetch: " . &Dumper ($xml));
}

# Its a bit fiddly but I just don't know how else to get an array of objects from a response.
# Process each node.
@nodes = $xml->{response}{data}->nodes;
undef $parsed_content;
foreach my $node (@nodes) {
    # Get all the arg value objects.
    my @arg_values = map $_->args_values, $node;
    my $content;
    # Map each arg value object key and content to a hash.
    map $content->{$_->key} = $_->content, @arg_values;

    # Handle nested elements.
    my @part_nodes = $xml->{response}{data}{row}->nodes;

    # Again don't know how to get these out nicely with XML::Smart.
    $content->{parts} = [];
    foreach my $part_node (@part_nodes) {
        my @part_arg_values = map $_->args_values, $part_node;
        my $part_content;
        map $part_content->{$_->key} = $_->content, @part_arg_values;
        push @{$content->{parts}}, $part_content;
    }

    push @{$parsed_content}, $content;
}

# Check that we only got one back!
eq_or_diff (scalar @{$parsed_content}, 1, 'XML Object Fetch singleton.');
if (! eq_or_diff (@{$parsed_content}[0], $expected, 'XML Object Fetch matches.')) {
    BAIL_OUT("Unexpected Duplicated Fetch result: " . &Dumper ($xml));
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
All Boats|5";

if (! eq_or_diff ($content, $expected, 'JSON FileDownload Plugin Content Check')) {
    BAIL_OUT("Unexpected FilePlugin result: " . &Dumper ($content));
}

###############################################################################
# This one is in the include1.xml file.
###############################################################################

$content = TestUtils::fetch ([ 'file_download2', $x_boat_class ]);

$expected = "Param|Value
App Name|demo
Interview|Secondary Alternative
Rest 0|file_download2
Rest 1|X Class
Boat Class|X Class
All Boats|5";

if (! eq_or_diff ($content, $expected, 'JSON FileDownload2 Plugin Content Check')) {
    BAIL_OUT("Unexpected FilePlugin result: " . &Dumper ($content));
}

###############################################################################
# This one is in the include2.xml file and demo.xml (takes precedence).
###############################################################################

$content = TestUtils::fetch ([ 'file_download3', $x_boat_class ]);

$expected = "Param|Value
App Name|demo
Interview|Cross-Sectional
Rest 0|file_download3
Rest 1|X Class
Boat Class|X Class
All Boats|5";

if (! eq_or_diff ($content, $expected, 'JSON FileDownload3 Plugin Content Check')) {
    BAIL_OUT("Unexpected FilePlugin result: " . &Dumper ($content));
}



done_testing ();
