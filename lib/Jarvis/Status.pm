###############################################################################
# Description:  Reports the status of the current session.  Are we logged-in,
#               what groups do we belong to, etc...
#
# Licence:
#       This file is part of the Jarvis WebApp/Database gateway utility.
#
#       Jarvis is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 3 of the License, or
#       (at your option) any later version.
#
#       Jarvis is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with Jarvis.  If not, see <http://www.gnu.org/licenses/>.
#
#       This software is Copyright 2008 by Jonathan Couper-Smartt.
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
    $fields{"username"} = $args{'username'};
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