use strict;
use warnings;

sub plugin::Demo::do {
    my ($jconfig, %args) = @_;

    my $output = "";

    # This demonstrates that the plugin can access Jarvis::Config info.
    $output = "APP: " . $jconfig->{'app_name'} . "\n";

    # This demonstrates XML-configured parameters to the plugin.
    $output .= "CAT: " . $args{'category'} . "\n";

    my $dbh = &Jarvis::DB::Handle ($jconfig);
    $output .= "Boats: " . $dbh->do("SELECT COUNT(*) FROM boat");

    return $output;
}

1;
