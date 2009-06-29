###############################################################################
# Description:
#       Jarvis supports pluggable Login modules.  This module checks server
#	environment variables to determine if the user has:
#
#	  - Basic Authentication remote user is as expected, and
#	  - OPTIONALLY: Has the correct remote IP address, and
#	  - OPTIONALLY: Accessed via HTTPS
#
#	For the last case, the server may have required them client
#	present a client certificate, but we don't know about that.
#
#	Note that to get certificate names mapping to BasicAuth, you
# 	can try the following http.conf.  See:
#
#		http://httpd.apache.org/docs/2.2/ssl/ssl_howto.html
#
#   <Directory /usr/local/apache2/htdocs/secure/area>
# 	SSLVerifyClient      require
# 	SSLVerifyDepth       5
# 	SSLCACertificateFile conf/ssl.crt/ca.crt
# 	SSLCACertificatePath conf/ssl.crt
# 	SSLOptions           +FakeBasicAuth
# 	SSLRequireSSL
# 	AuthName             "Snake Oil Authentication"
# 	AuthType             Basic
# 	AuthBasicProvider    file
# 	AuthUserFile         /usr/local/apache2/conf/httpd.passwd
# 	Require              valid-user
#   </Directory>
#
#	Then in httpd.passwd put:
#
#	/C=NZ/ST=Hastings/O=Woogloo/CN=Woogloo for N-Squared Access:xxj31ZMTZzkVA
#
#       Refer to the documentation for the "check" function for how
#       to configure your <application>.xml to use this login module.
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

use strict;
use warnings;

use Jarvis::Error;

package Jarvis::Login::BasicAuth;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# supplied by the server, specifically REMOTE_USER which is filled when the
# service is configured to use Apache Authentication.
#
# Note the use of FakeBasicAuth which ties SLL certificate DNs to basic
# auth names without passwords.
#
# To use this method, specify the following login parameters.
#
#    <app format="json" debug="no">
#        ...
#        <login module="Jarvis::Login::BasicAuth">
#	     # Default is "no", HTTPS not required.
#  	     <parameter name="require_https" value="yes"/>
#
#	     # Default is '', no remote IP checking.
#  	     <parameter name="remote_ip" value="192.168.1.1"/>
#
#	     # Default is '', no remote user checking.
#	     <parameter name="remote_user" value="Exact Common Name"/>
#
#	     # Default is '', (i.e. use the DEFAULT_USER basic auth username)
#  	     <parameter name="username" value="default"/>
#
#	     # Default is use a single group eponymous to the username.
#  	     <parameter name="group_list" value="default"/>
#        </login>
#        ...
#    </app>
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi
#               BasicAuth config indirectly via Jarvis::DB
#
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::BasicAuth::check {
    my ($jconfig, $username, $password, %login_parameters) = @_;

    # Our user name login parameters are here...
    my $require_https = defined ($Jarvis::Config::yes_value {lc ($login_parameters{'require_https'} || "no")});
    my $remote_ip = $login_parameters{'remote_ip'} || '';
    my $remote_user = $login_parameters{'remote_user'} || '';
    $username = $login_parameters{'username'};
    my $group_list = $login_parameters{'group_list'} || $username;

    # No check on username/password.  We don't require or expect them.  WE will
    # determine the username.
    if ($require_https && ! $jconfig->{'cgi'}->https()) {
        return ("Client must access over HTTPS for this login method.");
    }

    # Check the IP address first.
    if ($remote_ip ne '') {
        my $actual_ip = $ENV{"HTTP_X_FORWARDED_FOR"} || $ENV{"HTTP_CLIENT_IP"} || $ENV{"REMOTE_ADDR"} || '';
	if ($actual_ip ne $remote_ip) {
            return ("Access not authorized from actual remote IP address.");
	}
    }

    # Specific remote user?
    if ($remote_user ne '') {
        my $actual_user = $ENV{"REMOTE_USER"} || '';
	if ($actual_user ne $remote_user) {
            return ("Access not authorized for this user in BasicAuth login module.");
	}

    # Any remote user is permitted.
    } else {
        my $actual_user = $ENV{"REMOTE_USER"} || '';
        if ($actual_user eq '') {
            return ("No actual remote user provided by BasicAuth mechanism.");
        }
    }

    # Now determine which username to use.
    if (! $username) {
	$username = $remote_user;
    }
    if (! $username) {
        return ("No remote user and no configured default username.");
    }

    # And determine the group list.
    if (! $group_list) {
   	$group_list = $username;
    }

    return ("", $username, $group_list);
}

1;
