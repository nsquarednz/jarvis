###############################################################################
# Description:
#       Jarvis plugin that provides a list of events in JSON format in a 
#       format that Simile can read for its event timeline code (which is just
#       awesome).
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

package JarvisTracker::Events;

use JSON::PP;
use Jarvis::DB;

sub JarvisTracker::Events::do {
    my ($jconfig, $restArgs) = @_;
    
    my %events = (
        dateTimeFormat => 'iso8601'
    );

    my $limit = $jconfig->{cgi}->param('limit') || '500';
    $limit =~ /^[0-9]+$/ || die 'Error in parameters. Limit must be a number.';

    my @eventList;

    # Get some data.
    $jconfig->{format} = 'rows_aref';
    $jconfig->{dataset_name} = 'get_events';
    my $events = &Jarvis::Dataset::fetch ($jconfig);
    ref($events) ne 'ARRAY' && die $events; # If there was an error, this is an error message, not an array of data!

    my $counter = 0;
    foreach (@{$events}) {
        my $eventData = {
            icon => 'style/instant-timeline-event-icon.png',
            start => $_->{start_time},
            title => $_->{app_name} . '/' . ($_->{username} || '') . '/' . $_->{dataset},
            durationEvent => 'false',
            description => $_->{error}
        };

        $eventData->{end} = $_->{end_time} if $_->{instant} eq '0';
        $eventData->{durationEvent} = 'true' if $_->{instant} eq '0';
        $eventData->{color} = '#999' if $_->{dataset} =~ /^__/;
        $eventData->{color} = 'red' if length($_->{error}) > 0;

        push(@eventList, $eventData);

        $counter ++;
        last if $counter > $limit;
    }

    $events{'events'} = \@eventList;
    $events{'fetched'} = $counter;

    my $json = JSON::PP->new->pretty(1);
    return $json->encode ( \%events );
}


1;


