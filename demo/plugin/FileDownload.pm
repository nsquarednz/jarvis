use strict;
use warnings;

use Jarvis::Error;
use Jarvis::DB;

sub plugin::FileDownload::do {
    my ($jconfig, $rest_args, %plugin_args) = @_;
    
    my $rest0 = (defined $rest_args->{0}) ? $rest_args->{0} : '<undef>';
    my $rest1 = (defined $rest_args->{1}) ? $rest_args->{1} : '<undef>';
    my $rest2 = (defined $rest_args->{2}) ? $rest_args->{2} : '<undef>';
    my $rest3 = (defined $rest_args->{3}) ? $rest_args->{3} : '<undef>';
    my $boat_class = (defined $rest_args->{boat_class}) ? $rest_args->{boat_class} : '<undef>';

    my $app_name = $jconfig->{app_name};
    my $cgi_myval = $jconfig->{cgi}->param('myval');
    &Jarvis::Error::debug ($jconfig, "App Name: '%s'.", $app_name);
    &Jarvis::Error::dump ($jconfig, "CGI MyVal: '%s'.", $cgi_myval);
    my $interview = $plugin_args{interview} || 'Unknown';

    my $dbh = &Jarvis::DB::handle ($jconfig);
    my $rows = $dbh->selectall_arrayref ("SELECT COUNT(*) as count FROM boat", { Slice => {} });    
    my $all_boats = $$rows[0]{count};

    my $content = 
"Param|Value
App Name|$app_name
Interview|$interview
Rest 0|$rest0
Rest 1|$rest1
Rest 2|$rest2
Rest 3|$rest3
Boat Class|$boat_class
All Boats|$all_boats";

    return $content;
}

1;
