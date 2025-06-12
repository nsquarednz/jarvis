###############################################################################
# Description:  General purpose utility functions used by Jarvis routines.
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
#       This software is Copyright 2025 by Jonathan Couper-Smartt.
###############################################################################
#
use strict;
use warnings;

package Jarvis::Utils;

use Exporter 'import';
our @EXPORT_OK = qw(generate_uuid);


###############################################################################
# Public Functions
###############################################################################

###############################################################################
# Generate a random UUID. Avoid any reliance on 3rd party UUID generator Perl
# modules due to yum/apt availability issues on target platforms.
#
# The implementation is based on Perl's UUID::Tiny module, generating the UUID
# from random numbers.
###############################################################################
#
sub generate_uuid {
    my $uuid = '';
    for (1 .. 4) {
        my $top = int(rand(65536)) % 65536;
        my $bottom = int(rand(65536)) % 65536;
        $uuid .= pack 'I', (($top << 16) | $bottom);
    }
    substr $uuid, 6, 1, chr(ord(substr($uuid, 6, 1)) & 0x0f);
    substr $uuid, 8, 1, chr(ord(substr $uuid, 8, 1) & 0x3f | 0x80);
    return join '-', map { unpack 'H*', $_ } map { substr $uuid, 0, $_, '' } ( 4, 2, 2, 2, 6 );
}

1;
