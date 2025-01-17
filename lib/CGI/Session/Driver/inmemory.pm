###############################################################################
# Description:
#       A CGI::Session implementation for pure in-memory session data.
#       Useful as a shim for the Basic Authentication Jarvis login method
#
# Licence:
#       This file is part of the Jarvis WebApp/BasicAuth gateway utility.
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
use CGI;
package CGI::Session::Driver::inmemory;
use strict;
use base qw( CGI::Session::Driver CGI::Session::ErrorHandler );
sub init {
    my ($self) = @_;
    # optional
}
sub DESTROY {
    my ($self) = @_;
    # optional
}
sub store {
    my ($self, $sid, $datastr) = @_;
    # Store $datastr, which is an already serialized string of data.
    return 1;
}
sub retrieve {
    my ($self, $sid) = @_;
    # Return $datastr, which was previously stored using above store() method.
    # Return $datastr if $sid was found. Return 0 or "" if $sid doesn't exist
    return 0;
}
sub remove {
    my ($self, $sid) = @_;
    # Remove storage associated with $sid. Return any true value indicating success,
    # or undef on failure.
    return 1;
}
sub traverse {
    my ($self, $coderef) = @_;
    # execute $coderef for each session id passing session id as the first and the only
    # argument
    return 1;
}
1;
