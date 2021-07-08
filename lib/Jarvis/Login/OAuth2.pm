###############################################################################
# Description:
#       Functions for dealing with OAuth login and user authentication.
#
#       This login method will accept a one time access code for purposes
#       of retrieving a users access token from an OAuth provider.
#
# License:
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
#       This software is Copyright 2021 by Jonathan Couper-Smartt.
###############################################################################
#
#   In order to use this module the following dependencies must be installed:
#       libjson-webtoken-perl
#       libio-socket-ssl-perl
#       libcrypt-ssleay-perl
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
use IO::Socket::SSL;

###############################################################################
# Helper Functions
###############################################################################

###############################################################################
# Simple function to get an instance of a LWP UserAgent object for purposes
# of communicating with external OAuth endpoints.
#
# Params:
#       $self_signed_cert - Optional self signed certificate path
#                           to use when constructing an SSL based user agent.
#
# Returns:
#       LWP::UserAgent
###############################################################################
sub get_user_agent {
    my ($self_signed_cert) = @_;

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

    return $ua;
}

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing OAuth code.
# We validate this by first calling an OAuth Token endpoint to retrieve a valid
# access, refresh and ID token.
# Once we have valid tokens we contact the extended OAuth token
# endpoint to query additional permissions.
#
# To use this method, specify the following login parameters.
#
#    <app format="json" debug="no">
#        ...
#           <login module="Jarvis::Login::OAuth2">
#               <parameter name="client_secret"      value="<client_secret>"/>
#               <parameter name="client_id"          value="<client_id>"/>
#               <parameter name="site"               value="<oauth_provider_base_site>"/>
#               <parameter name="token_path"         value="/auth/realms/<realm>/protocol/openid-connect/token"/>
#               <parameter name="logout_path"        value="/auth/realms/<realm>/protocol/openid-connect/logout"/>
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

    # We might have also been given an encoded POSTDATA object.
    if (my $post_data = $jconfig->{'cgi'}->param('POSTDATA')) {
        # If we have POSTDATA lets try and decode it as JSON.
        eval {
            my $post_json = decode_json ($post_data);
            $auth_code = $post_json->{'code'};
        };
        if ($@) {
            die "Failed to parse non application/json POSTDATA";
        }

    }

    # If we have a defined OAuth code lets proceed with trying to do our token grant and introspection.
    if (defined $auth_code) {

        # At this stage lets sanity check that all the required items we need are defined.
        my $client_secret= $login_parameters{client_secret} || die ("client_secret must be defined.\n");
        my $client_id    = $login_parameters{client_id}     || die ("client_id must be defined.\n");
        my $site         = $login_parameters{site}          || die ("site must be defined.\n");
        my $token_path   = $login_parameters{token_path}    || die ("token_path must be defined.\n");
        my $redirect_uri = $login_parameters{redirect_uri}  || die ("redirect_uri must be defined.\n");

        # Optional fields.
        my $self_signed_cert = $login_parameters{self_signed_cert};

        # At this stage we have everything we need to send a request on to our token request endpoint. Lets construct this now.
        my $ua = get_user_agent ($self_signed_cert);

        # Construct the token endpoint.
        my $token_endpoint = $site . $token_path;

        # Create our outbound request and construct our data.
        my $token_request_data = {
            client_id       => $client_id
            , client_secret => $client_secret
            , code          => $auth_code
            , redirect_uri  => $redirect_uri
            , grant_type    => 'authorization_code'
            , scope         => 'openid'
        };

        # Trigger our token request.
        my $token_response = $ua->post ($token_endpoint, $token_request_data);

        # Check for success.
        if ($token_response->is_success) {

            # Parse the JSON contents of the response.
            my $token_message      = $token_response->decoded_content;
            my $token_message_json = JSON::XS::decode_json($token_message);

            # Pull the access token out of the request, we can use that to get information on the token associated with the user to get their
            # groups and other information that we need.
            my $access_token  = $token_message_json->{access_token}  || die ("Authorization token repose did not contain an access token.\n");
            my $refresh_token = $token_message_json->{refresh_token} || die ("Authorization token repose did not contain a refresh token.\n");
            my $id_token      = $token_message_json->{id_token}      || die ("Authorization token repose did not contain an id token.\n");

            # Store each of the tokens we receive on the session. We will need these in future requests.
            $jconfig->{session}->param ("access_token" , $access_token);
            $jconfig->{session}->param ("refresh_token", $refresh_token);
            $jconfig->{session}->param ("id_token"     , $id_token);

            # Decode the ID token using our token library. This contains user identifying information that we can access and use.
            my $decoded_id_token =JSON::WebToken->decode ($id_token, undef, 0, 'none');

            # Also decode the refresh token, it will hold our session expiry time.
            my $decoded_refresh_token =JSON::WebToken->decode ($refresh_token, undef, 0, 'none');

            # Extract values as needed.
            my $username = $decoded_id_token->{preferred_username};

            # Update the expiry stored against our session.
            $decoded_refresh_token->{'exp'} || die ("Refresh token does not contain an expiry time.\n");
            $jconfig->{session}->expire ($decoded_refresh_token->{'exp'});

            # Grab our user groups. This might be a string or an array or even undefined so lets be careful.
            my $user_groups = '';
            if (defined $decoded_id_token->{groups}) {
                if (ref $decoded_id_token->{groups} eq 'ARRAY') {
                    $user_groups = join (',', @{$decoded_id_token->{groups}});

                } else {
                    $user_groups = $decoded_id_token->{groups};
                }
            }

            # Once we've done everything that we can with the tokens that we currently have
            # we need to send a request to the token endpoint so we can request our extended permissions.
            my $extended_token_request_data = {
                grant_type    => 'urn:ietf:params:oauth:grant-type:uma-ticket'
                , audience => $client_id
            };

            # This type of endpoint is special. We have to include our access token as authorization to query this information.
            # The LWP user agent is a bit weird with how this works for setting headers. Anything after the first parameter can be a header definition.
            # This continues until the 'Content' property is detected at which point it is encoded as the post data.
            my $extended_token_response = $ua->post ($token_endpoint, 'Authorization' => "Bearer $access_token", Content => $extended_token_request_data);

            my $extended_token_message      = $extended_token_response->decoded_content;
            my $extended_token_message_json = JSON::XS::decode_json($extended_token_message);

            # Check if the response contains the access token we expect.
            my $extended_access_token = $extended_token_message_json->{access_token};

            # If we have no extended access token we won't bail out. There are situations where they might have a valid login but no permissions.
            if (defined $extended_access_token) {
                  # Decode the token using our token library.
                my $decoded_extended_access_token =JSON::WebToken->decode ($extended_access_token, undef, 0, 'none');

                # Sanity check.
                $decoded_extended_access_token->{authorization}{permissions} || die ("RPT Token missing authorization permissions.");

                # Convert our permissions objects array to a list of associated permissions.
                my @permission_names = map { $_->{rsname} } @{$decoded_extended_access_token->{authorization}{permissions}};

                # Associate the list of permissions against our Jarvis session. Implementing applications can access this as required.
                $jconfig->{session}->param ("oauth_permissions", \@permission_names);
            }

            # Finally return our successful login indicator to our calling module providing the user name and groups we got back.
            return ("", $username, $user_groups);

        } else {
            die ("Failed to contact token endpoint: [" . ($token_response->code ? $token_response->code : 500) . "] " . ($token_response->message ? $token_response->message : "") . "\n");
        }
    }
}

################################################################################
# Optional method definition for refresh operations.
# This method is invoked by the parent Login module if we are
# logged in and invoking the status endpoint.
#
# This implementation contacts the token endpoint requesting a token refresh.
# This refresh operation will provide updated tokens and extend the expiry of our
# access token.
#
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
#       $error_string or undef
################################################################################
#
sub Jarvis::Login::OAuth2::refresh {
    my ($jconfig, %login_parameters) = @_;

    # Sanity check that our login parameters specify all the configuration that we need.
    my $token_path    = $login_parameters{token_path}                || die ("token_path must be defined.\n");
    my $client_id     = $login_parameters{client_id}                 || die ("client_id must be defined.\n");
    my $client_secret = $login_parameters{client_secret}             || die ("client_secret must be defined.\n");
    my $site          = $login_parameters{site}                      || die ("site must be defined.\n");
    my $refresh_token = $jconfig->{session}->param ('refresh_token');

    # No refresh token? This can happen, no point in trying.
    if (! defined ($refresh_token)) {
        return undef;
    }

    # Optional fields.
    my $self_signed_cert = $login_parameters{self_signed_cert};

    # Get our user agent.
    my $ua = get_user_agent ($self_signed_cert);

    # Construct the refresh endpoint.
    my $token_endpoint = $site . $token_path;

    # Create our outbound request and construct our data.
    my $refresh_request_data = {
        refresh_token   => $refresh_token
        , client_id     => $client_id
        , client_secret => $client_secret
        , grant_type    => 'refresh_token'
    };

    my $token_refresh_response = $ua->post ($token_endpoint, $refresh_request_data);

    # Check for success, in failure cases we'll return a tailored error message.
    if ($token_refresh_response->is_success) {

        # Decode the message so we can get our updated tokens.
        my $token_refresh_message      = $token_refresh_response->decoded_content;
        my $token_refresh_message_json = JSON::XS::decode_json($token_refresh_message);

        # Update each of the stored tokens as they now have a newer time stamp.
        $jconfig->{session}->param ("access_token" , $token_refresh_message_json->{access_token});
        $jconfig->{session}->param ("refresh_token", $token_refresh_message_json->{refresh_token});
        $jconfig->{session}->param ("id_token"     , $token_refresh_message_json->{id_token});

        # We do have to parse the refresh token as we do need to update the expire time on our CGI session.
        my $decoded_refresh_token =JSON::WebToken->decode ($token_refresh_message_json->{refresh_token}, undef, 0, 'none');
        $decoded_refresh_token->{'exp'} || die ("Refresh token does not contain an expiry time.\n");

        # Update the expiry stored against our session.
        $jconfig->{session}->expire ($decoded_refresh_token->{'exp'});

    } else {
        # Some thing went wrong, try and extract and error.
        my $error_message;
        eval {
            my $refresh_request_failure      = $token_refresh_response->decoded_content;
            my $refresh_request_failure_json = JSON::XS::decode_json($refresh_request_failure);
            $error_message = $refresh_request_failure_json->{error};
        };
        return ($error_message ? 'Refresh Failed: ' . $error_message : 'Refresh Failed: Unknown Error Occurred');

    }

    return undef;
}


################################################################################
# Optional method definition for logout operations.
# This method is invoked by the parent Login module if we are
# are logging out and have an existing session.
#
# This implementation contacts the logout endpoint requesting an invalidation
# of our access tokens before we clear our Jarvis session.
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
#       $error_string or undef
################################################################################
#
sub Jarvis::Login::OAuth2::logout {
    my ($jconfig, %login_parameters) = @_;

    # Sanity check that our login parameters specify all the configuration that we need.
    my $logout_path   = $login_parameters{logout_path}               || die ("logout_path must be defined.\n");
    my $client_id     = $login_parameters{client_id}                 || die ("client_id must be defined.\n");
    my $client_secret = $login_parameters{client_secret}             || die ("client_secret must be defined.\n");
    my $site          = $login_parameters{site}                      || die ("site must be defined.\n");
    my $refresh_token = $jconfig->{session}->param ('refresh_token');
    my $access_token  = $jconfig->{session}->param ('access_token');

    # No tokens, lets skip as this can happen.
    if (! defined ($refresh_token) || ! defined ($access_token)) {
        return undef;
    }

    # Optional fields.
    my $self_signed_cert = $login_parameters{self_signed_cert};

    # Get our user agent.
    my $ua = get_user_agent ($self_signed_cert);

    # Construct the logout endpoint.
    my $logout_endpoint = $site . $logout_path;

    # Create our outbound request and construct our data.
    my $logout_request_data = {
        refresh_token   => $refresh_token
        , client_id     => $client_id
        , client_secret => $client_secret
    };

    # This type of endpoint is special. We have to include our access token as authorization to query this information.
    # The LWP user agent is a bit weird with how this works for setting headers. Anything after the first parameter can be a header definition.
    # This continues until the 'Content' property is detected at which point it is encoded as the post data.
    my $logout_response = $ua->post ($logout_endpoint, 'Authorization' => "Bearer $access_token", Content => $logout_request_data);

    # We're looking for any sort of success here. Some may implement a code 200, others might just acknowledge our success with a 204.
    # We're only going to have an issue if we don't have a success otherwise we're done here.
    if (! $logout_response->is_success) {
        # Attempt to extract an error message.
        my $error_message;
        eval {
            my $logout_failure      = $logout_response->decoded_content;
            my $logout_failure_json = JSON::XS::decode_json($logout_failure);
            $error_message = $logout_failure_json->{error};
        };
        return ($error_message ? 'Logout Failed: ' . $error_message : 'Logout Failed: Unknown Error Occurred');
    }

    return undef;
}

1;
