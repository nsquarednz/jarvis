use strict;
use warnings;

sub plugin::Demo::do {
    my ($jconfig, $restArgs, %args) = @_;

    my $output = "";

    &Jarvis::Error::debug ($jconfig, "Running the Demo plugin.");

    # This demonstrates that the plugin can access Jarvis::Config info.
    $output .= "APP: " . $jconfig->{'app_name'} . "\n";
    $output .= "Username: " . $jconfig->{'username'} . "\n";
    $output .= "CGI myval: " . ($jconfig->{'cgi'}->param('myval') || '') . "\n";

    # This demonstrates XML-configured parameters to the plugin.
    $output .= "CAT: " . $args{'category'} . "\n";

    # This demonstrates accessing RESTful arguments that are 
    # from the URL after the dataset name
    my $counter = 0;
    map {
        $output .= "RESTful argument $counter: " . $restArgs->[$counter] . "\n";
        $counter++;
    } @{$restArgs};

    my $dbh = &Jarvis::DB::handle ($jconfig);
    $output .= "Boats: " . $dbh->do("SELECT COUNT(*) FROM boat");

    return $output;
}

1;
