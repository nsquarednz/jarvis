###############################################################################
# Description:  Makefile for Jarvis JSON interface functions.
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
#       This software is Copyright 2019 by Jonathan Couper-Smartt.
###############################################################################
#
use ExtUtils::MakeMaker;

#
# Here, if we're targeting centos/Redhat enterprise, we need to use Lua from 
# a non-standard package, installed into /DBA/. We need to set up some path
# details
#
my $is_centos = 0;
$is_centos = 1 if -e "/etc/redhat-release";
my $INC = $is_centos ? '-I/DBA/lua/5.2.1/include' : '-I/usr/include/lua5.2';
my $LIBS = $is_centos ? [ '-L/DBA/lua/5.2.1/lib -llua' ] : [ '-llua5.2' ];

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
   AUTHOR => '(c) 2019 by Jonathan Couper-Smartt.', 
   NAME => 'Jarvis::JSON::Utils',
   VERSION => '1.0', # Version for compatibility.
   LIBS => $LIBS,
   DEFINE => '', # e.g., '-DHAVE_SOMETHING'
   CCFLAGS => "$Config{ccflags} -Wall -Wno-strict-aliasing",
   INC => $INC
);
