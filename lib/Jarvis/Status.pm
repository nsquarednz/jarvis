#NOT FOR RUNNING AS CGI
#
# Description:  Reports the status of the current request.
#
###############################################################################
#
use strict;
use warnings;

use JSON::XS;
use XML::Smart;

package Jarvis::Status;

use Jarvis::Text;

################################################################################
# Shows our current connection status.
#
# Params: Hash of Args (* indicates mandatory)
#       *logged_in, *user-name, *error_string, *group_list
#
# Returns:
#       1.
#       die on error.
################################################################################
#
sub Report {
    my (%args) = @_;

    my %fields = ();
    $fields{"logged_in"} = $args{'logged_in'};
    $fields{"user_name"} = $args{'user_name'};
    $fields{"error_string"} = $args{'error_string'};
    $fields{"group_list"} = $args{'group_list'};

    my @data = (\%fields);

    if ($args{'format'} eq "json") {
        my %return_hash = ( "data" => \@data );
        my $json = JSON::XS->new->pretty(1);
        return $json->encode ( \%return_hash );

    } else {
        my $xml = XML::Smart->new ();
        $xml->{data} = \@data;

        return $xml->data ();
    }
}

1;