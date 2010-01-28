###############################################################################
# Description:
#       Jarvis plugin to provide some general details on the type of dataset
#       an application name dataset is -
#
#       call with appname as REST parameter 1, and the dataset name as REST
#       parameter 2, and the resulting JSON will include data in an object,
#       and the dataset type (one of 'e', 'i', 'p', 's'):
#
#       {
#           name = 'dataset_name',
#           type = 'e'
#       }
#
# Licence:
#       This file is part of the Jarvis Tracker application.
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
#       This software is Copyright 2008 by Jamie Love.
###############################################################################

use strict;
use warnings;

package JarvisTracker::DatasetInfo;

use JSON::PP;

sub JarvisTracker::DatasetInfo::do {
    my ($jconfig, $restArgs) = @_;

    my @restArgs = @{$restArgs};

    if (scalar(@restArgs) < 2) {
        die "Please provide application name as REST arg  1, and the dataset directory as following REST arg.";
    }

    # Check that each part is safe. We can't have the user
    # passing in paths that could let them access files outside
    # the application directories.
    map {
        die "ERROR in path provided. Path must be made up of characters: A-Z, a-z, 0-9, _, - and space only." if ! /^[-A-Za-z0-9_ ]*$/;
    } @restArgs;

    my $app = shift @restArgs;

    my %info = (
        name => join ".", @restArgs
    );

    if ($restArgs[0] =~ /^\__/) {
        $info{'type'} = 'i';
    } elsif (scalar(@restArgs) > 1) {
        $info{'type'} = 's';
    } else {
        my $xmlFilename = $jconfig->{'etc_dir'} . "/" . $app . ".xml";
        my $xml = XML::Smart->new ($xmlFilename) || die "Cannot read configuration for $app.xml: $!.";

        my $exec = $xml->{jarvis}{app}{exec}('dataset', 'eq', $restArgs[0]);
        if ($exec) {
            $info{'type'} = 'e';
        } else {
            my $plugin = $xml->{jarvis}{app}{plugin}('dataset', 'eq', $restArgs[0]);
            if ($plugin) {
                $info{'type'} = 'p';
            } else {
                $info{'type'} = 's';
            }
        }
    }

    my $json = JSON::PP->new->pretty(1);
    return $json->encode ( \%info );
}


1;

