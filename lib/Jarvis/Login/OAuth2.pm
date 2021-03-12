###############################################################################
# Description:
#       Functions for dealing with OAuth login and user authentication.
#
#       This login method will accept a one time access code for purposes
#       of retreiving a users access token from an OAuth provider.
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
#       This software is Copyright 2020 by Jonathan Couper-Smartt.
###############################################################################
#
#   In order to use this module the following dependencies must be installed:
#       libjson-webtoken-perl
#
use strict;
use warnings;

use CGI;
use CGI::Cookie;

package Jarvis::Login::OAuth2;

use LWP::UserAgent;
use URI::Escape;
use JSON::XS;
use Net::SSL;
use Data::Dumper;
use JSON::WebToken;
###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing OAuth code.
# We validate this by first calling an OAuth Token endpoint to retrieve a valid
# access token.
# Once we have our access token we contact an OAuth Token Introspection endpoint
# to check the validity of the access token as well as retrieving additional
# information on the user we have requested information for.
#
# To use this method, specify the following login parameters.
#
#    <app format="json" debug="no">
#        ...
#           <login module="Jarvis::Login::OAuth2">
#               <parameter name="client_secret"      value="<client_secret>"/>
#               <parameter name="client_id"          value="<client_id>"/>
#               <parameter name="site"               value="<oauth_provider_base_site>"/>
#               <parameter name="token_path"         value="/oauth2/token"/>
#               <parameter name="introspection_path" value="/oauth2/introspect"/>
#               <parameter name="introspection_user" value="<introspection_user_or_client_id>"/>
#               <parameter name="introspection_pass" value="<introspection_user_or_client_secret>"/>
#               <parameter name="redirect_uri"       value="<application_redirect_uri>"/>
#               <!-- Optional self signed cert path if the oauth provider is using a self signed cert. -->
#               <parameter name="self_signed_cert"   value="<path_to_self_signed_cert>"/>
#           </login>
#        ...
#    </app>
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi
#
#       %login_parameters - Hash of login parameters parsed from
#               the master application XML file by the master Login class.
#
# Returns:
#       ($error_string or "", $username or "", "group1,group2,group3...")
################################################################################
#
sub Jarvis::Login::OAuth2::check {
    my ($jconfig, %login_parameters) = @_;

    # Check if we were provided an OAuth code.
    my $auth_code = $jconfig->{'cgi'}->param('code');

    # If we have a defined OAuth code lets proceed with trying to do our token grant and introspection.
    if (defined $auth_code) {

        # At this stage lets sanity check that all the required items we need are defined.
        my $client_secret      = $login_parameters{client_secret}      || die ("client_secret must be defined.\n");
        my $client_id          = $login_parameters{client_id}          || die ("client_id must be defined.\n");
        my $site               = $login_parameters{site}               || die ("site must be defined.\n");
        my $token_path         = $login_parameters{token_path}         || die ("token_path must be defined.\n");
        my $redirect_uri       = $login_parameters{redirect_uri}       || die ("redirect_uri must be defined.\n");
        my $introspection_path = $login_parameters{introspection_path} || die ("introspection_path must be defined.\n");
        my $introspection_user = $login_parameters{introspection_user} || die ("introspection_user must be defined.\n");
        my $introspection_pass = $login_parameters{introspection_pass} || die ("introspection_pass must be defined.\n");

        # Optional fields.
        my $self_signed_cert = $login_parameters{self_signed_cert};

        # At this stage we have everyting we need to send a request on to our token request endpoint. Lets construct this now.

        # Define our UserAgent.
        my $ua = LWP::UserAgent->new;

        # If for instance we have a self signed cert the SSL library will reject it unless we trust the cert.
        # If a cert path is provided allow it now.
        if ($self_signed_cert) {

            # Sanity check the provided PEM file actually exists.
            -f $self_signed_cert || die ("Provided self signed PEM file does not exist.\n");

            # Enable the PEM against our SSL options.
            $ua->ssl_opts (
                SSL_ca_file     => $self_signed_cert,
                verify_hostname => 0
            );
        }

        # Construct the token endpoint.
        my $token_endpoint = $site . $token_path;

        # Create our outbound request and construct our data.
        my $post_data = {
            client_id       => $client_id
            , client_secret => $client_secret
            , grant_type    => 'authorization_code'
            , code          => $auth_code
            , redirect_uri  => $redirect_uri
            , scope         => 'openid'
        };

        # Trigger our token request.
        my $token_response = $ua->post($token_endpoint, $post_data);

        # Check for success.
        if ($token_response->is_success) {

            # Parse the JSON contents of the response.
            my $token_message      = $token_response->decoded_content;
            my $token_message_json = JSON::XS::decode_json($token_message);

            # Pull the access token out of the request, we can use that to get information on the token associated with the user to get their
            # groups and other information that we need.
            my $access_token = $token_message_json->{access_token} || die ("Authorization token repose did not contain an access token.\n");

            # Construct our introspection endpoint URI.
            my $introspection_endpoiont = $site . $introspection_path;

            # Create our outbound request and construct our data.
            my $introspection_post_data = "token=$access_token";

            # Construct our introspection request. Here we explicitally create an HTTP Request as we need to set authorization.
            my $introspection_request = HTTP::Request->new ( POST => $introspection_endpoiont);

            # Set username and password auth.
            $introspection_request->authorization_basic ($introspection_user, $introspection_pass);

            # Set body content.
            $introspection_request->content ($introspection_post_data);

            # Fire off our request.
            my $introspection_response = $ua->request ($introspection_request);

            # Check for success.
            if ($introspection_response->is_success) {

                # Parse the JSON contents of the response.
                my $introspection_message      = $introspection_response->decoded_content;
                my $introspection_message_json = JSON::XS::decode_json($introspection_message);

                # Fetch the username from the message JSON.
                my $username = $introspection_message_json->{username};

                # Check if our response contains an OPEN ID token.
                $token_message_json->{id_token} || die ("Token introspection response did not contain an OpenID token.\n");

                # Decode the token using our token library.
                my $decoded_token =JSON::WebToken->decode($token_message_json->{id_token}, undef, 0, 'none');

                # Grab our user groups.
                my $user_groups = $decoded_token->{groups} ? $decoded_token->{groups} : [];

                # Finally return our successful login indicator to our calling module providing the username and groups we got back.
                return ("", $username, $user_groups);

            } else {
                die ("Failed to contact introspection endpoint: [" . ($introspection_response->code ? $introspection_response->code : 500) . "] " . ($introspection_response->message ? $introspection_response->message : "") . "\n");
            }
        } else {
            die ("Failed to contact token endpoint: [" . ($token_response->code ? $token_response->code : 500) . "] " . ($token_response->message ? $token_response->message : "") . "\n");
        }
    }
}
1;
