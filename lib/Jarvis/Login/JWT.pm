###############################################################################
# Description:
#
#       Functions for dealing with JWT login and user authentication.
#
#       This module supports the following JWT authorization flows:
#
#       Basic:
#           Provided a JWT token validate the token structure and content
#           based on known configuration. After validation grant application
#           access with standard CGI session cookies.
#
# License:
#
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
#       along with Jarvis. If not, see <http://www.gnu.org/licenses/>.
#
#       This software is Copyright 2023 by Jonathan Couper-Smartt.
#
###############################################################################
#
use strict;
use warnings;

use CGI;
use CGI::Cookie;

package Jarvis::Login::JWT;

use JSON::XS;
use Data::Dumper;
use JSON::WebToken;

###############################################################################
# Helper Functions
###############################################################################

# Helper function to fetch the public key file off disk.
sub get_validation_key {
    my ($jconfig, $path) = @_;
    # Sanity checks.
    -f $path or die "Validation Key $path does not exist.\n";

    # Load the content.
    open (FH, '<', $path) || die ("Failed to open Validation Key: '$!'.\n");
    read FH, my $validation_key_string, -s FH;
    close (FH);

    return $validation_key_string;
}

###############################################################################
# AUTH FUNCTIONS
###############################################################################

#
# Handle processing for a JWT token that is encoded using RFC 7519 encoding.
# See: https://datatracker.ietf.org/doc/html/rfc7519
#
sub processRfc7519Token {
    my ($jconfig, %login_parameters) = @_;

    # Parse parameters.
    my $validate_token        = $login_parameters{validate_token}       // 0;
    my $validation_key        = $login_parameters{validation_key};
    my $validation_algorithms = $login_parameters{validation_algorithms};
    my $username_key          = $login_parameters{username_key}         || 'username';
    my $external_user_id_key  = $login_parameters{external_user_id_key} || 'username';
    my $groups_key            = $login_parameters{groups_key}           || 'groups';
    my $expiry_key            = $login_parameters{expiry_key}           || 'expiry';
    my $token_path            = $login_parameters{token_path}           || 'token';

    # If validating the token ensure key path is specified.
    if ($validate_token) {
        (defined ($validation_key) and defined ($validation_algorithms)) or die ("validation_key and validation_algorithms must be defined if validate_token is set.\n");
    }

    # Attempt to locate the token.
    my $token = $jconfig->{'cgi'}->param($token_path);

    # We might have also been given an encoded POSTDATA object.
    if (my $post_data = $jconfig->{'cgi'}->param('POSTDATA')) {
        # If we have POSTDATA lets try and decode it as JSON.
        eval {
            my $post_json = decode_json ($post_data);
            $token = $post_json->{$token_path};
        };
        if ($@) {
            die "Failed to parse non application/json POSTDATA";
        }
    }

    # Provided a token via either GET or POST? Attempt to parse and handle it.
    if (defined $token) {

        # Since we already have the contained JWT we need to parse it. We either:
        #   Parse it using the provided public key information to validate that we have a valid key from who says signed it.
        #   Parse it as is without additional validation.
        my $decoded_token;

        if ($validate_token) {
            # Load the configured public key.
            my $key = get_validation_key ($jconfig, $validation_key);

            # Standard parsing with validation requirements.
            eval {
                $decoded_token = JSON::WebToken->decode ($token, $key, 1, $validation_algorithms);
            };
            if ($@) {
                die "Failed to decode Token: $@\n";
            }

        } else {
            # Standard parsing.
            eval {
                $decoded_token = JSON::WebToken->decode ($token, undef, 0, 'none');
            };
            if ($@) {
                die "Failed to decode Token: $@\n";
            }
        }

        # At this stage we should have a decoded JWT token, either validated or invalidated but we should have something we can use.
        # Does the token have a valid expiry?
        my $expiry_timestamp = $decoded_token->{$expiry_key} or die ("JWT Token does not contain expiry timestamp key '$expiry_key'.\n");

        # Token expired? Reject.
        if ($expiry_timestamp < time ()) {
            die ("Provided JWT Token has expired.\n");
        }

        # Attempt to pull bits out of the token that we need.
        # Username is required.
        my $username = $decoded_token->{$username_key} or die ("JWT Token does not contain username key '$username_key'.\n");

        # External ID is required.
        my $external_user_id = $decoded_token->{$external_user_id_key} or die ("JWT Token does not contain external user ID key '$external_user_id_key'.\n");

        # Grab our user groups. This might be a string or an array or even undefined so lets be careful.
        # Don't die on this being missing as they could have no groups and that is valid although not useful.
        my $user_groups;
        if (defined ($groups_key) && defined ($decoded_token->{$groups_key})) {
            if (ref ($decoded_token->{$groups_key}) eq 'ARRAY') {
                $user_groups = join (',', @{$decoded_token->{$groups_key}});

            } else {
                $user_groups = $decoded_token->{$groups_key};
            }
        }

        # Store the username information against the session this will let us configure permissions as required.
        # This authentication type only supports internal authentication and for now exports both as the username.
        #
        # UPN maps to a known username, whereas the user ID is usually some external identifier.
        $jconfig->{session}->param ('external_user_id'       , $external_user_id);
        $jconfig->{session}->param ('external_user_principle', $username);

        # Finally return our successful login indicator to our calling module providing the user name and groups we got back.
        return ("", $username, $user_groups);

    } else {
        # Nothing to check return all empty elements. This is often the case for calls to things like our __status endpoint to query session information.
        return ("", "", "");
    }
}

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".
#
# The operations we perform depends on our operating configuration.
#
# BASIC
#
#   In this case we look for a provided token in the request noted by the configured source parameter.
#   If enabled we validate the token using the provided public key information.
#   Decode the token checking the expiry timestamp information.
#   Pull source username and group data from the decoded token as configured.
#   Bootstrap the CGI session using the parsed data.
#
#   To use this method, specify the following login parameters.
#
#      <app format="json" debug="no">
#          ...
#             <login module="Jarvis::Login::JWT">
#                  <parameter name="token_type"            value="rfc7519"/>
#                  <parameter name="token_path"            value="token"/>
#                  <parameter name="validate_token"        value="1"/>
#                  <parameter name="validation_key"        value="/etc/jarvis/signing_public_key"/>
#                  <parameter name="validation_algorithms" value="HS256"/>
#                  <parameter name="username_key"          value="username"/>
#                  <parameter name="external_user_id_key"  value="username"/>
#                  <parameter name="groups_key"            value="group"/>
#                  <parameter name="expiry_key"            value="timestamp"/>
#             </login>
#          ...
#      </app>
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi
#
#       %login_parameters - Hash of login parameters parsed from the parent application XML file by the parent Login class.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
#
################################################################################
#
sub Jarvis::Login::JWT::check {
    my ($jconfig, %login_parameters) = @_;

    # Load base parameters this will determine how the token is processed.
    my $token_type = $login_parameters{token_type} // 'rfc7519';

    # Check for a supported token type.
    if ($token_type eq 'rfc7519') {
        return processRfc7519Token ($jconfig, %login_parameters);

    } else {
        die ("JWT Module Unsupported Token Type: '$token_type'");
    }

    # No login actions. Return.
    return ("", "", undef);
}

# The JWT Login module does not specify an override for the 'refresh' method. All refresh handling is performed by the Login base class.

# The JWT Login module does not specify an override for the 'logout' method. All logout handling is performed by the Login base class.

1;
