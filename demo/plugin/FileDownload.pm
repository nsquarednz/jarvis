use strict;
use warnings;

use Jarvis::Error;
use Jarvis::DB;

sub plugin::FileDownload::do {
    my ($jconfig, $user_args, %plugin_args) = @_;
    
    # User args includes numbered and named REST args.
    my $rest0 = (defined $user_args->{0}) ? $user_args->{0} : '<undef>';
    my $rest1 = (defined $user_args->{1}) ? $user_args->{1} : '<undef>';
    my $boat_class = (defined $user_args->{boat_class}) 
                     ? $user_args->{boat_class} : '<undef>';

    # User args also includes the CGI-supplied parameters.
    my $app_name = $jconfig->{app_name};
    my $cgi_myval = (defined $user_args->{cgi_myval}) 
                     ? $user_args->{cgi_myval} : '<undef>';

    &Jarvis::Error::debug ($jconfig, "App Name: '%s'.", $app_name);
    &Jarvis::Error::dump ($jconfig, "CGI MyVal: '%s'.", $cgi_myval);
    my $interview = $plugin_args{interview} || 'Unknown';

    my $dbh = &Jarvis::DB::handle ($jconfig);
    my $rows = $dbh->selectall_arrayref ("SELECT COUNT(*) as count FROM boat", 
                                         { Slice => {} });    

    my $num_boats = $$rows[0]{count};
    my $content = 
"Param|Value
App Name|$app_name
Interview|$interview
Rest 0|$rest0
Rest 1|$rest1
Boat Class|$boat_class
All Boats|$num_boats";

    return $content;
}

1;
