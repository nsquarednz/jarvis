#!/usr/bin/perl
###############################################################################
# Description:
#       Wrapper for standard CGI (without using mod_perl) to perform a Jarvis
#       request.
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
use strict;
use warnings;

use CGI::Fast;
use CGI::Carp qw(set_die_handler);

use Carp;
$Carp::CarpLevel = 1;

# If "/usr/share/jarvis" is not your root jarvis directory, then either change
# this script by hand, or preferably set the environment variable in your
# webserver config.  E.g. in apache, add the following line (without the
# leading hash).
#
# SetEnv JARVIS_ROOT "/path/to/jarvis"
#
my $jarvis_root;
BEGIN { 
    $jarvis_root = $ENV{'JARVIS_ROOT'} || "/usr/share/jarvis";

    #
    # A strange feature of CGI::Fast seems to be to silently incorporate
    # CGI::Carp in the deployment. CGI::Carp adds the date and script name
    # to all dies, and it does this before calling our Main.pm die handler
    #
    # To avoid this happening, we overwrite the CGI::Carp die handler and
    # so that instead of doing all the logic it thinks we want, it simply
    # and immediately passes handling up to our Main.pm die handler.
    #
    sub cgi_carp_die_override {
        CORE::die(@_);
    }
    set_die_handler(\&cgi_carp_die_override);
}

use lib "$jarvis_root/lib";

use Jarvis::Main;

###############################################################################
# Main Program
###############################################################################
#
while (my $cgi = CGI::Fast->new ()) {
    &Jarvis::Main::do ({ cgi => $cgi });
}

1;
