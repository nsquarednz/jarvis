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

use JSON::PP;           # JSON::PP was giving double-free/corruption errors.
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
#
# Returns:
#       1.
#       die on error.
################################################################################
#
sub report {
    my ($jconfig) = @_;

    my %fields = ();
    $fields{"logged_in"} = $jconfig->{'logged_in'};
    $fields{"username"} = $jconfig->{'username'};
    $fields{"error_string"} = $jconfig->{'error_string'};
    $fields{"group_list"} = $jconfig->{'group_list'};
    $fields{"sid"} = $jconfig->{'sid'};

    my $extra_href = {};
    my $return_text = undef;
    &Jarvis::Hook::return_status ($jconfig, $extra_href, \$return_text);

    foreach my $name (sort (keys %$extra_href)) {
        $fields {$name} = $extra_href->{$name};
    }

    if ($return_text) {
        &Jarvis::Error::debug ($jconfig, "Return content determined by hook ::return_fetch");
        return $return_text;

    } elsif ($jconfig->{'format'} eq "json") {
        my $json = JSON::PP->new->pretty(1);
        my $json_string = $json->encode ( \%fields );
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($json_string));
        &Jarvis::Error::dump ($jconfig, $json_string);
        return $json_string;

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{'response'} = \%fields;

        my $xml_string = $xml->data ();
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($xml_string));
        &Jarvis::Error::dump ($jconfig, $xml_string);
        return $xml_string;

    } else {
        die "Unsupported format '" . $jconfig->{'format'} ."' in Status::report\n";
    }
}

1;