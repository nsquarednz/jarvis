###############################################################################
# Description:
#       A plugin for doing a reverse DNS lookup for one or more IP addresses.
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

package JarvisTracker::ReverseDnsLookup;

my %CACHE;

sub doLookup {
    my $ip = shift;
    return $ip unless $ip=~/\d+\.\d+\.\d+\.\d+/; # TODO - deal with IPv6 addresses.
    unless (exists $CACHE{$ip}) {
        my @h = eval <<'END';
            local $SIG{ALRM} = sub {die "timeout\n"};
            alarm(2);
            my @i = gethostbyaddr(pack('C4',split('\.',$ip)), 2);
            alarm(0);
            @i;
END
        if ($@) {
            die unless $@ eq "timeout\n"; # die for real if it wasn't the special timeout trigger.
        } else {
            $CACHE{$ip} = $h[0] || undef;
        }
    }
    return $CACHE{$ip} || $ip;
}

sub JarvisTracker::ReverseDnsLookup::do {
    my ($jconfig, $restArgs) = @_;

    my @listOfIpAddresses = $jconfig->{'cgi'}->param('ip_address');
    my %addresses;
    map {
        $addresses{$_} = doLookup ($_);
    } @listOfIpAddresses;

    my $json = JSON::PP->new->pretty(1);
    return $json->encode ( { data => \%addresses } );
}

1;
