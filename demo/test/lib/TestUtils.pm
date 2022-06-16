#!/usr/bin/perl
#
# Nested Dataset unit tests against demo app database.
#
use strict;
use warnings;

package TestUtils;

use LWP::UserAgent;
use HTTP::Cookies;
use Data::Dumper;
use JSON qw(encode_json decode_json);
use URI::Escape;
use XML::Smart;

# Define the base URL to use. Calling scripts may overwrite this if required. 
# Docker test runners run on different ports so we'll need this for those cases.
$TestUtils::base_url = "http://localhost/jarvis-agent/demo";

my %passwords = ("admin" => "admin", "guest" => "guest");

my $JSON_SENT_MIME_TYPE = "application/json";

my $JSON_RETURNED_MIME_TYPE = "application/json";

# This user agent will perform all our tests.
my $ua = LWP::UserAgent->new;
$ua->cookie_jar (HTTP::Cookies->new (file => "cookies.txt", autosave => 1));

################################################################################
# Perform a logout as part of a test.
#
# Params:
#		<None>
#
# Returns:
#       Returned $json (die on error)
################################################################################
#
sub logout_json {

	# Request is a simple GET.
 	my $req = HTTP::Request->new (GET => "$TestUtils::base_url/__logout");

 	# Check request succeeded, and result is interpretable as JSON.
 	my $res = $ua->request ($req);
 	($res->is_success) || die "Failed: __status: " . $res->status_line . "\n" . $res->content;
 	($res->header ('Content-Type') =~ m|^$JSON_RETURNED_MIME_TYPE|) || die "Wrong Content-Type: " . $res->header ('Content-Type');
 	my $json = decode_json ($res->content ());

 	# Check this looks like a valid response.
 	(defined $json->{logged_in}) || die "Missing 'logged_in' in response: " . &Dumper ($json);

 	return $json;
}

################################################################################
# Perform a login request.
#
# Params:
#		$username - Must a be a known username.  We will supply the password.
#
# Returns:
#       Returned JSON OBJECT (die on error)
################################################################################
#
sub login_json {
	my ($username) = @_;

	# Username and password are sent.
	my $password = $passwords{$username} || die "Unknown user: $username";
	my %query_args = (username => $username, password => $password);
	my $urlencoded_form = join ('&', map { uri_escape ($_) . '=' . uri_escape ($query_args{$_}) } (keys %query_args));

	# Request is a POST with user/pass.
 	my $req = HTTP::Request->new (POST => "$TestUtils::base_url/__status");
    $req->content_type ('application/x-www-form-urlencoded');
    $req->content ($urlencoded_form); 	

 	# Check request succeeded, and result is interpretable as JSON.
 	my $res = $ua->request ($req);
 	($res->is_success) || die "Failed: __status: " . $res->status_line . "\n" . $res->content;
 	($res->header ('Content-Type') =~ m|^$JSON_RETURNED_MIME_TYPE|) || die "Wrong Content-Type: " . $res->header ('Content-Type');
 	my $json = decode_json ($res->content ());

 	# Check this looks like a valid response.
 	(defined $json->{logged_in}) || die "Missing 'logged_in' in response: " . &Dumper ($json);

 	return $json;
}

################################################################################
# Perform a fetch, with specified args.  Assumes we are logged in already.
#
# Params:
#		$url_parts - Array of URL parts, dataset plus any restful args.  We will encode.
#		$query_args - Hash of CGI args.
#
# Returns:
#       Returned $content (die on error)
################################################################################
#
sub fetch {
	my ($url_parts, $query_args, $returned_content_type) = @_;

	# Query args are sent to a restful url.
	my $restful_url = join ('/', map { uri_escape ($_) } @$url_parts);
	my $urlencoded_args = join ('&', map { uri_escape ($_) . '=' . uri_escape ($query_args->{$_}) } (keys %$query_args));

	# Request is a GET with query args in the URL.
 	my $req = HTTP::Request->new (GET => "$TestUtils::base_url/$restful_url?$urlencoded_args");

  	# Check request succeeded, and result is interpretable as JSON.
	my $res = $ua->request ($req);
 	($res->is_success) || die "Failed: $restful_url: " . $res->status_line . "\n" . $res->content;
 	my $expected_content_type = $returned_content_type // 'text/plain';
 	($res->header ('Content-Type') =~ m|^$expected_content_type|) || die "Wrong Content-Type: " . $res->header ('Content-Type');

 	return $res->content ();
}

################################################################################
# Perform a fetch, with specified args.  Assumes we are logged in already.
#
# Params:
#		$url_parts - Array of URL parts, dataset plus any restful args.  We will encode.
#		$query_args - Hash of CGI args.
#
# Returns:
#       Returned JSON OBJECT (die on error)
################################################################################
#
sub fetch_json {
	my ($url_parts, $query_args) = @_;

	my $content = &fetch ($url_parts, $query_args, $JSON_RETURNED_MIME_TYPE);

 	my $json = decode_json ($content);
 	(defined $json->{logged_in}) || die "Missing 'logged_in' in response: " . &Dumper ($json);

 	return $json;
}

################################################################################
# Perform a fetch, with specified args.  Assumes we are logged in already.
#
# Params:
#		$url_parts - Array of URL parts, dataset plus any restful args.  We will encode.
#		$query_args - Hash of CGI args.
#
# Returns:
#       Returned XML::Smart OBJECT (die on error)
################################################################################
#
sub fetch_xml {
	my ($url_parts, $query_args) = @_;

	$query_args->{format} = 'xml';
	my $content = &fetch ($url_parts, $query_args, 'application/xml');

 	my $xml = XML::Smart->new ($content);
 	(defined $xml->{response}{logged_in}) || die "Missing 'logged_in' in response: " . &Dumper ($xml);

 	return $xml;
}

################################################################################
# Perform a store, with specified args and content.  Assumes we are logged in already.
#
# Params:
#		$url_parts - Array of URL parts, dataset plus any restful args.  We will encode.
#		$query_args - Hash of CGI args.
#		$rows - Array of rows to modify.
#		$fail - Do we expect this to fail?
#
# Returns:
#       IF $fail   - return ($code, $message) (die on success)
#		IF ! $fail - return $json (die on error)
################################################################################
#
sub store {
	my ($url_parts, $query_args, $content, $fail, $sent_content_type, $returned_content_type) = @_;

	# Query args are sent to a restful url.
	my $restful_url = join ('/', map { uri_escape ($_) } @$url_parts);
	my $urlencoded_args = join ('&', map { uri_escape ($_) . '=' . uri_escape ($query_args->{$_}) } (keys %$query_args));

	# Request is a POST with query args in the URL and a content.
 	my $req = HTTP::Request->new (POST => "$TestUtils::base_url/$restful_url?$urlencoded_args");
    $req->content_type ($sent_content_type);
    $req->content ($content);
	my $res = $ua->request ($req);
 
 	return $res;
}

sub store_json {
	my ($url_parts, $query_args, $rows, $fail) = @_;

	my $encoded_content = encode_json ($rows);

	my $content = &store ($url_parts, $query_args, $encoded_content, $fail, $JSON_SENT_MIME_TYPE, $JSON_RETURNED_MIME_TYPE);

	if ($fail) {
	 	($content->is_success) && die "Expected failure - got success.";
	 	return ($content->code, $content->content);

	} else {
	 	($content->is_success) || die "Failed: " . $content->status_line . "\n" . $content->content;
	 	($content->header ('Content-Type') =~ m|^text/plain|) || die "Wrong Content-Type: " . $content->header ('Content-Type');

	 	my $json = decode_json ($content->content ());
	 	(defined $json->{logged_in}) || die "Missing 'logged_in' in response: " . &Dumper ($json);

	 	return $json;
	} 	
}

sub store_xml {
	my ($url_parts, $query_args, $rows, $fail) = @_;

	my $encoded_content = XML::Smart->new ();
	$encoded_content->{request} = $rows;
	$encoded_content = $encoded_content->data ();	

	$query_args->{format} = 'xml';
	my $content = &store ($url_parts, $query_args, $encoded_content, $fail, 'application/xml', 'application/xml');


	if ($fail) {
	 	($content->is_success) && die "Expected failure - got success.";
	 	return ($content->code, $content->content);

	} else {
	 	($content->is_success) || die "Failed: " . $content->status_line . "\n" . $content->content;
	 	($content->header ('Content-Type') =~ m|^text/plain|) || die "Wrong Content-Type: " . $content->header ('Content-Type');


	 	my $xml = XML::Smart->new ($content->content ());
	 	(defined $xml->{response}{logged_in}) || die "Missing 'logged_in' in response: " . &Dumper ($xml);

 		return $xml;
	} 	
}

1;