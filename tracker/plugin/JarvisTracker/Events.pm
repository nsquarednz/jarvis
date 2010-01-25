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

    my @eventList;

    # Get some data.
    my $dbh = &Jarvis::DB::handle ($jconfig);
    my $sql = <<EOF;
SELECT 
    strftime('%Y-%m-%d %H:%M:%f',start_time) AS start_time, 
    strftime('%Y-%m-%d %H:%M:%f',start_time + duration_ms * (1.0 / (1000 * 60 * 60 * 24))) AS end_time, 
    (CASE WHEN duration_ms < 1000 THEN '1' ELSE '0' END) as instant,
    app_name, 
    username, 
    dataset 
FROM 
    request 
WHERE 
    (? IS NULL OR sid = ?)
    AND (? IS NULL OR username = ?)
LIMIT 500
EOF
    my $sth = $dbh->prepare ($sql) || die "Couldn't prepare statement for retrieving events: " . $dbh->errstr;
    my $stm = {};
    $stm->{sth} = $sth;
    $stm->{ttype} = 'JarvisTrackerEvents';
    my $params = [
        $jconfig->{cgi}->param('sid') || undef
        , $jconfig->{cgi}->param('sid') || undef
        , $jconfig->{cgi}->param('user') || undef
        , $jconfig->{cgi}->param('user') || undef
    ];
    &Jarvis::Dataset::statement_execute ($jconfig, $stm, $params);
    $stm->{'error'} && die "Unable to execute statement for retrieving events: " . $stm->{'error'};

    my $users = $sth->fetchall_arrayref({});
    map {
        my $eventData;
        if ($_->{instant} eq '1') {
            $eventData = {
                start => $_->{start_time},
                title => $_->{app_name} . '/' . $_->{username} . '/' . $_->{dataset},
                durationEvent => 'false',
                description => ''
            };
        } else {
            $eventData = {
                start => $_->{start_time},
                end => $_->{end_time},
                title => $_->{app_name} . '/' . $_->{username} . '/' . $_->{dataset},
                durationEvent => 'true',
                description => ''

            };
        }

        push(@eventList, $eventData);
    } @{$users};

    $events{'events'} = \@eventList;

    my $json = JSON::PP->new->pretty(1);
    return $json->encode ( \%events );
}


1;


