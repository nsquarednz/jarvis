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
use Jarvis::Error;

################################################################################
# Shows our current connection status.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ: logged_in, username, error_string, group_list
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       1.
#       die on error.
################################################################################
#
sub report {
    my ($jconfig, $rest_args_aref) = @_;

    my %fields = ();
    $fields{"logged_in"} = $jconfig->{'logged_in'};
    $fields{"username"} = $jconfig->{'username'};
    $fields{"error_string"} = $jconfig->{'error_string'};
    $fields{"group_list"} = $jconfig->{'group_list'};

    if ($jconfig->{'format'} eq "json") {
        my $json = JSON::XS->new->pretty(1);
        return $json->encode ( \%fields );

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{root} = \%fields;

        return $xml->data ();

    } else {
        die "Unsupported format '" . $jconfig->{'format'} ."' in Status::report\n";
    }
}

1;