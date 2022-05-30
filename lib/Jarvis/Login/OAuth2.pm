###############################################################################
# Description:
#       Functions for dealing with OAuth login and user authentication.
#
#       This OAuth login module currently supports to Authorization Code Flows.
#
#       Confidential:
#           This login method will accept a one time access code for purposes
#           of retrieving a users access token from an OAuth provider.
#
#       Public:
#           This login method will accept a bearer token on each request
#           the first time this is seen it is validated and confirmed using the
#           OAuth providers public key and then stored in the session.
#           Subsequent attempts will check the key hash has not changed.
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
use strict;
use warnings;

use CGI;
use CGI::Cookie;

package Jarvis::Login::OAuth2;

use LWP::UserAgent;
use URI::Escape;
use JSON::XS;
use Data::Dumper;
use JSON::WebToken;
use Jarvis::Error;
use IO::Socket::SSL;
use Time::HiRes qw (gettimeofday tv_interval);
use Digest::MD5 qw(md5_hex);
use Crypt::OpenSSL::RSA;
use MIME::Base64 qw (decode_base64url decode_base64);

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
# Helper function that will handle getting our auth public key.
# This method will check to see if we have a cached key on disk in a tmp file.
#
# If no file is present or the file is too old we will fetch from the configured
# endpoint.
#
# Otherwise we will fetch it off disk and just pass it back.
#
# Params:
#       %login_parameters - Hash reference of login parameters passed through.
#
# Returns:
#       Public key string.
#
###############################################################################
sub get_auth_public_key {
    my ($jconfig, %login_parameters) = @_;

    # Get all of the base parameters we'll need.
    my $site                        = $login_parameters{site}                        || die ("OAuth2 module 'site' must be defined.\n");
    my $public_key_path             = $login_parameters{public_key_path}             || die ("OAuth2 module 'public_key_path' must be defined.\n");
    my $public_key_store            = $login_parameters{public_key_store}            // '/tmp/auth_public_key';
    my $public_key_lifetime_seconds = $login_parameters{public_key_lifetime_seconds} // 600;

    # Optional fields.
    my $self_signed_cert = $login_parameters{self_signed_cert};

    # We store the public key in a storage file. We need to check that it exists and that its lifetime doesn't
    # exceed our configured amount. If either of those aren't valid then we fetch a new key and store it.
    my $public_key_store_valid = 0;
    # First check existence.
    if (-f $public_key_store ) {
        # Next get mod information to determine the file age in seconds.
        my $public_key_mod_time = [(stat($public_key_store))[9], 0];
        my $public_key_age = tv_interval ($public_key_mod_time, [gettimeofday]);
        if ($public_key_age < $public_key_lifetime_seconds) {
            $public_key_store_valid = 1;
        }
    }

    # If the key store has valid timing lets go ahead and load it.
    if ($public_key_store_valid) {
        # Load the contents of the key file and return it. Nice and easy.
        open (FH, '<', $public_key_store) || die ("Failed to open public key store: '$!'.\n");
        read FH, my $public_keys_string, -s FH;
        close (FH);

        # Load the public key data from JSON, validating correct JSON.
        my $public_keys;
        eval {
            $public_keys = JSON::XS::decode_json ($public_keys_string)
        };
        if ($@) {
            # Invalid key.
            &Jarvis::Error::log ($jconfig, "Failed to parse public key store data: '$@'.");
            $public_key_store_valid = 0;
        }

        # Still valid?
        if ($public_key_store_valid) {
            # Simply return.
            return $public_keys;
        }
    }

    # If we make it here then either we had no key store, the key store was out of date, or the key we loaded was not valid.
    # Go ahead and fetch a new one.
    # Fetch a user agent.
    my $ua = get_user_agent ($self_signed_cert);

    # Construct the public key endpoint.
    my $public_key_endpoint = $site . $public_key_path;

    # Trigger the request.
    my $public_key_response = $ua->get ($public_key_endpoint);

    # Check for success.
    if ($public_key_response->is_success) {
        # Parse the JSON contents of the response. We will store this.
        my $public_key_message = $public_key_response->decoded_content;

        # Sanity check what we got is actually valid JSON before we store it.
        my $public_key_json;
        eval {
            $public_key_json = JSON::XS::decode_json ($public_key_message);
        };
        if ($@) {
            &Jarvis::Error::log ($jconfig, "Failed to Retrieve Public Key Data: '$@'.");
            die "Failed to Retrieve Public Key Data.\n";
        }

        # Lets be nice and process the JSON data keying it off the 'kid' field. This is the key that will be used by the tokens to indicate the key used.
        # Here we also need to pull apart the key information and generate a public key mapping.
        # Here we also check our supported algorithms:
        #   RSA
        #
        my $public_keys;
        foreach my $key (@{$public_key_json->{keys}}) {
            my $key_data;

            # Check for supported type.
            if ($key->{kty} eq 'RSA') {
                # Using our RSA module generate the key information from the modulus and exponent information provided to us.
                my $rsa = Crypt::OpenSSL::RSA->new_key_from_parameters (
                    Crypt::OpenSSL::Bignum->new_from_bin(decode_base64url ($key->{n}))
                    , Crypt::OpenSSL::Bignum->new_from_bin(decode_base64url ($key->{e}))
                );

                # Store needed properties.
                $key_data = {
                    public_key => $rsa->get_public_key_string ()
                    , supported_algorithms => [
                        'RSA'
                        , 'RS256'
                        , 'RS384'
                        , 'RS512'
                    ]
                }
            } else {
                die "Unsupported JWKS Key Type: $key->{kty}\n";
            }

            $public_keys->{$key->{kid}} = $key_data;
        }
        my $public_keys_string = JSON::XS::encode_json ($public_keys);

        # Write to our temp file.
        open (FH, '>', $public_key_store) || die ("Failed to open public key store.\n");
        print FH $public_keys_string;
        close (FH);

        # Return the public key data to the callee. They'll need to decide which key they need.
        return $public_keys;

    } else {
        die ("Failed to contact public key endpoint: [" . ($public_key_response->code ? $public_key_response->code : 500) . "] " . ($public_key_response->message ? $public_key_response->message : "") . "\n");
    }
}

###############################################################################
# AUTH FUNCTIONS
###############################################################################
sub performPublicAuth {
    my ($jconfig, %login_parameters) = @_;

    # Check if we were provided an Authorization header.
    my $authorization_header = $ENV{HTTP_AUTHORIZATION};
    if ($authorization_header) {

        # Get required fields for pulling apart the JWT token.
        my $groups_key          = $login_parameters{groups_key}          || die ("OAuth2 module 'groups_key' must be defined for public access type.\n");
        my $username_key        = $login_parameters{username_key}        || die ("OAuth2 module 'username_key' must be defined for public access type.\n");
        my $user_identifier_key = $login_parameters{user_identifier_key} || die ("OAuth2 module 'user_identifier_key' must be defined for public access type.\n");

        # Clear bearer information. We only want the key.
        $authorization_header =~ s/Bearer\s?//;

        # Pull apart the JWT. We should have three parts divided by a . character. This gives us the header, payload and signature.
        my ($header_segment, $payload_segment, $signature_segment) = split (/\./, $authorization_header);

        # We need information from the header which is normally not parsed and returned so lets do it ourselves.
        my $header;
        eval {
            $header = JSON::XS::decode_json (decode_base64 ($header_segment));
        };
        if ($@) {
            die "Failed to decode Authorization Token Header: $@\n";
        }

        # If we managed to decode the header we need to algorithm used, this will let us validate against the public key.
        # As well as the "kid" field. This maps directly to the public key we have stored.
        my $header_kid = $header->{kid} // die "Authorization Token Header missing 'kid'\n";

        # First things first lets hash the auth header so we can check if its the same as one that might already be stored.
        my $authorization_header_hash = md5_hex ($authorization_header);

        # Get the auth providers public keys. We will use one of these to validate the token.
        my $public_keys = get_auth_public_key ($jconfig, %login_parameters);

        # Attempt to locate the key we want.
        my $public_key_data = $public_keys->{$header_kid} // die "Authorization Token Header with KID '$header_kid' not found in public keys.\n";

        # Grab the key information itself.
        my $public_key           = $public_key_data->{public_key}           // die "Authroziation Token Header with KID '$header_kid' references public key without public key information.\n" ;
        my $supported_algorithms = $public_key_data->{supported_algorithms} // die "Authroziation Token Header with KID '$header_kid' references public key without supported algorithm information.\n" ;

        # Attempt to decode the auth header. This is were we validate it against the public key. If this step fails for any reason
        # we will not continue the authorization and fail hard.
        my $decoded_authorization_token;
        eval {
            $decoded_authorization_token = JSON::WebToken->decode ($authorization_header, $public_key, 1, $supported_algorithms);
        };
        if ($@) {
            die "Failed to decode Authorization Token: $@\n" . Dumper ($public_key) . Dumper ($supported_algorithms) . Dumper ($authorization_header);
        }

        # Start fetching information that we will store in our session. We will parse various parts and store it.
        # First lets hash the auth token and store that. This will let us skip all the parsing steps if the token is still valid and hasn't changed.
        my $username = $decoded_authorization_token->{$username_key} || die ("Authroziation Token does not contain '$username_key' information.\n");

        # Grab our user groups. This might be a string or an array or even undefined so lets be careful.
        my $user_groups = '';
        if (defined $groups_key && defined $decoded_authorization_token->{$groups_key}) {
            if (ref $decoded_authorization_token->{$groups_key} eq 'ARRAY') {
                $user_groups = join (',', @{$decoded_authorization_token->{$groups_key}});

            } else {
                $user_groups = $decoded_authorization_token->{$groups_key};
            }
        }

        # Grab the expiry time of the token.
        my $token_expiry = $decoded_authorization_token->{exp} || die ("Authorization Token does not contain an expiry time.\n");
        # Validate that the token is still actually valid.
        if ($token_expiry < gettimeofday) {
            $jconfig->{status} = "401 Unauthorized";
            die "Authorization Token is expired.\n";
        }

        # Grab the external ID of the user that we performed auth for.
        my $external_user_id = $decoded_authorization_token->{$user_identifier_key} || die ("Authorization Token does not contain '$user_identifier_key' information.\n");

        # Store session properties.
        $jconfig->{session}->param ("token_expiry", $token_expiry);
        $jconfig->{session}->param ("current_auth_token_hash", $authorization_header_hash);
        $jconfig->{session}->param ('external_user_id', $external_user_id);
        # Store the item from our user name key on the session. This maps to what will be our user principle.
        $jconfig->{session}->param ('external_user_principle', $username);

        # Finally return our successful login indicator to our calling module providing the user name and groups we got back.
        return ("", $username, $user_groups);
    } else {
	# No idea if we're logged in or not. Return all blanks.
        return ("", "", "");
    }
}

sub performConfidentialAuth {
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
            my $decoded_id_token = JSON::WebToken->decode ($id_token, undef, 0, 'none');

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
    } else {
	# No idea if we're logged in or not. Return all blanks.
	# Potentially this should error for the confidential flow?
	# But I think this can be called on __status/__habitat which should
	# not fail if not logged in
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
# CONFIDENTIAL FLOW
#
#   In this case we look at CGI variables
#   for the existing OAuth code.
#   We validate this by first calling an OAuth Token endpoint to retrieve a valid
#   access, refresh and ID token.
#   Once we have valid tokens we contact the extended OAuth token
#   endpoint to query additional permissions.
#
#   To use this method, specify the following login parameters.
#
#      <app format="json" debug="no">
#          ...
#             <login module="Jarvis::Login::OAuth2">
#                   <parameter name="grant_type"         value="auth_code"/>
#                   <parameter name="access_type"        value="confidential"/>
#                   <parameter name="client_secret"      value="<client_secret>"/>
#                   <parameter name="client_id"          value="<client_id>"/>
#                   <parameter name="site"               value="<oauth_provider_base_site>"/>
#                   <parameter name="token_path"         value="/auth/realms/<realm>/protocol/openid-connect/token"/>
#                   <parameter name="logout_path"        value="/auth/realms/<realm>/protocol/openid-connect/logout"/>
#                   <parameter name="redirect_uri"       value="<application_redirect_uri>"/>
#                   <!-- Optional self signed cert path if the oauth provider is using a self signed cert. -->
#                   <parameter name="self_signed_cert"   value="<path_to_self_signed_cert>"/>
#             </login>
#          ...
#      </app>
#
# PUBLIC FLOW
#
#   In this case we expect to receieve an access token in an Authorization bearer token.
#   We validate this token using a public retreived from the service provider and then pull it apart
#   storing the information in our session. We expect a token provided with each subsequent request which
#   we will match against a stored hash to determine if it has been updated and needs to be re-parsed.
#
#   To use this method, specify the following login parameters.
#
#      <app format="json" debug="no">
#          ...
#             <login module="Jarvis::Login::OAuth2">
#                   <parameter name="grant_type"                  value="auth_code"/>
#                   <parameter name="access_type"                 value="public"/>
#                   <parameter name="site"                        value="<oauth_provider_base_site>"/>
#                   <parameter name="public_key_path"             value="/auth/realms/<realm>"/>
#                   <parameter name="public_key_key"              value="public_key"/>
#                   <parameter name="public_key_store"            value="/tmp/auth_public_key"/>
#                   <parameter name="public_key_lifetime_seconds" value="600"/>
#                   <parameter name="groups_key"                  value="groups"/>
#                   <parameter name="self_signed_cert"            value="<path_to_self_signed_cert>"/>
#             </login>
#          ...
#      </app>
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

    # Load base parameters. Fall back to confidential auth code setups to support existing deployments.
    my $grant_type  = $login_parameters{grant_type}  // 'auth_code';
    my $access_type = $login_parameters{access_type} // 'confidential';

    # Check for a supported grant type.
    if ($grant_type eq 'auth_code') {

        # Check for supported access types.

        #
        # The public OAuth flow is where the token key exchange is handled by the client.
        # We are only passed the resulting access token which we will validate using the server providers public key.
        # We parse this key and store it within our session information and periodically update the information if the access token changes.
        # We expect the access token passed to us with every request via an authorization bearer header.
        #
        if ($access_type eq 'public') {
            return performPublicAuth ($jconfig, %login_parameters);

        #
        # The confidential OAuth flow is were we are passed an authorization code by the client and we handle the key exchange ourselves
        # with the service provider. We exchange the token along with a secret key to get a token that we can then pull apart
        # to load our service. We update this only periodically and store all the information in our CGI session.
        #
        } elsif ($access_type eq 'confidential') {
            return performConfidentialAuth ($jconfig, %login_parameters);

        } else {
            die ("OAuth2 Module Unsupported Access Type: '$access_type'");
        }
    } else {
        die ("OAuth2 Module Unsupported Grant Type: '$grant_type'");
    }

    # No login actions. Return.
    return ("", "", undef);
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

    # Load base parameters. Fall back to confidential auth code setups to support existing deployments.
    my $grant_type  = $login_parameters{grant_type}  // 'auth_code';
    my $access_type = $login_parameters{access_type} // 'confidential';

    # Check for a supported grant type.
    if ($grant_type eq 'auth_code') {

        # Check for supported access types.
        if ($access_type eq 'public') {

            # Check if we were provided an Authorization header.
            my $authorization_header = $ENV{HTTP_AUTHORIZATION};

            # No auth header present anymore and we have a valid session? Terminate.
            if ($authorization_header) {

                # Get a hash of the provided header.
                # If it matches the existing one and it hasn't expired we can just allow it through.
                my $authorization_header_hash          = md5_hex ($authorization_header);
                my $existing_authorization_header_hash = $jconfig->{session}->param ("current_auth_token_hash");
                my $existing_token_expiry              = $jconfig->{session}->param ("token_expiry");
                my @now                                = gettimeofday;

                # Matches?
                if (defined $existing_authorization_header_hash && $existing_authorization_header_hash eq $authorization_header_hash) {
                    # Expired?
                    if ($existing_token_expiry > $now[0]){
                        # Header matches and is still valid. Nice and easy return undef.
                        return undef;
                    } else {
                        # Lets be nice and dump some debug.
                        &Jarvis::Error::debug ($jconfig, "Refresh triggered for expired token for user: '$jconfig->{username}'");
                        # Token has since expired. Clear the session data and return an error.
                        Jarvis::Login::logout ($jconfig);
                        $jconfig->{status} = "401 Unauthorized";
                        # Return an error.
                        die ("Session Expired");
                    }

                    # We have an existing session and the header hashes match. Nice and easy return undef nothing else to do here.
                    return undef;
                } else {
                    # Got a new token? We need to perform the standard login validation logic for that new token.
                    # Trigger a logout to remove all state associated with the previous token. We need to rebuild it.
                    Jarvis::Login::logout ($jconfig);
                    # Trigger a new login with the new token.
                    Jarvis::Login::check ($jconfig);
                }
            } else {
                # No auth header? No longer a valid session. Trigger a logout to remove all state associated with what may have been a previous token.
                Jarvis::Login::logout ($jconfig);
                # Return an error.
                return "No Authroziation Header Provided";
            }

        } elsif ($access_type eq 'confidential') {

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

        } else {
            die ("OAuth2 Module Unsupported Access Type: '$access_type'");
        }
    } else {
        die ("OAuth2 Module Unsupported Grant Type: '$grant_type'");
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

    # Load base parameters. Fall back to confidential auth code setups to support existing deployments.
    my $grant_type  = $login_parameters{grant_type}  // 'auth_code';
    my $access_type = $login_parameters{access_type} // 'confidential';

    # Check for a supported grant type.
    if ($grant_type eq 'auth_code') {

        # Check for supported access types. We only have to perform specific logic for our confidential endpoint.
        # For public flows we simply return and allow Jarvis to clear our session information.
        if ($access_type eq 'confidential') {
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
        }
    }

    return undef;
}

1;
