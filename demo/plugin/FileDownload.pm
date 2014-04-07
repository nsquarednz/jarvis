use strict;
use warnings;

sub plugin::FileDownload::do {
    my ($jconfig, $rest_args, %args) = @_;
    
    my $content = "
Name|Age
Stephen|45
Patrick|43";

    return $content;
}

1;
