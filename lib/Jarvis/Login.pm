###############################################################################
# Description:  This is a wrapper which loads and hands off to a specific
#               login module depending on the login protocol being used.
#
#               We will check for session cookies, and will only require login
#               if we can't locate an active valid session.
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
#
use strict;
use warnings;

use CGI;
use CGI::Session;
use CGI::Cookie;
use DBI;

package Jarvis::Login;

use JSON qw(decode_json);
use Jarvis::Error;
use Jarvis::Text;
use Jarvis::Main qw(generate_uuid);

################################################################################
# Checks to see if we are logged in.  If permitted, we will create a new
# session if possible.
#
# If we do a login, this will extend/modify some parameters in our Jasper::Config
# object to show our current login status.
#
# Params:
#       $jconfig   - Jasper::Config object
#           READS
#               Database config indirectly via Login Modules and Jarvis::DB
#
#           WRITES
#               logged_in           Did a user log in?
#               offered_username    What username did we get offered?
#               username            Which user successfully logged in?
#               error_string        What error if not logged in?
#               group_list          Comma-separated group list.
#               session             The session object.
#               sname               Name of the session cookie.  Default "CGISESSID".
#               sid                 Session ID.  A big long number.
#               cookie              CGI::Cookie objects to send back with session info.
#
#       $override_href - Optional hash of override parameters.
#           username - Login with this username to use instead of CGI parameter
#           password - Login with this username to use instead of CGI parameter
#           force_relogin - Ignore any existing "logged_in" session.
################################################################################
#
sub check {
    my ($jconfig, $override_href) = @_;

    ###############################################################################
    # Login Process.  Get our existing session cookie if we have one.
    #
    # Note that you can disable the Jarvis sessiondb cookie store if your login
    # module uses its own cookie store.  Do that simply be removing the
    # <sessiondb> tag entirely.
    #
    # Drupal6 with (allow_login=no) is an example of when you might not wish
    # Jarvis to manage its own cookies.
    ###############################################################################
    #
    my $axml = $jconfig->{'xml'}->find ('./jarvis/app')->pop ();
    (defined $axml) || die "Cannot find <jarvis><app> in '" . $jconfig->{'app_name'} . ".xml'!\n";

    if ($axml->exists ('./sessiondb')) {

        # Where are our sessions stored?
        my $sid_store = $axml->findvalue ('./sessiondb/@store') || "driver:file;serializer:default;id:md5";
        &Jarvis::Error::debug ($jconfig, "SID Store '$sid_store'.");

        # die Data::Dumper::Dumper ($sid_store);

        my $default_cookie_name = uc ($jconfig->{'app_name'}) . "_CGISESSID";
        my $sid_cookie_name = $axml->findvalue ('./sessiondb/@cookie') || $default_cookie_name;

        CGI::Session->name($sid_cookie_name);
        &Jarvis::Error::debug ($jconfig, "SID Cookie Name '$sid_cookie_name'.");

        my %sid_params = ();
        if ($axml->exists ('./sessiondb/parameter')) {
            foreach my $sid_param ($axml->findnodes ('./sessiondb/parameter')) {
                $sid_params {$sid_param->{'name'}} = $sid_param->{'value'};
            }
        }

        # Find the session ID. Look up the source options configured.
        # by default look only in the cookie.
        #
        # To trigger a new login overriding any cookie that may exist
        # (if configured to look up cookies), configure the order as 'url,cookie'
        # and send a URL with the relevant parameter, but empty.
        my @sid_sources = map { lc (&trim($_)) } split (',', ($axml->findvalue ('./sessiondb/@sid_source') || "cookie"));
        my $sid = undef;
        foreach my $source (@sid_sources) {
            $sid = $jconfig->{'cgi'}->param($sid_cookie_name) if $source eq 'url';
            $sid = $jconfig->{'cgi'}->cookie($sid_cookie_name) if $source eq 'cookie';
            if (defined $sid) {
                $jconfig->{'sid_source'} = $source;
                last;
            }
        }
        &Jarvis::Error::debug ($jconfig, "SID Source: " . ($jconfig->{'sid_source'} || "none"));

        # Get an existing/new session.
        # Under windows, avoid having CGI::Session throw the error:
        # 'Your vendor has not defined Fcntl macro O_NOFOLLOW, used at C:/Perl/site/lib/CGI/Session/Driver/file.pm line 26.'
        # by hiding the signal handler.

        my $err_handler = $SIG{__DIE__};
        $SIG{__DIE__} = sub {};

        my $session = new CGI::Session ($sid_store, $sid, \%sid_params);
        # If we have CSRF Protection enabled and we are not logged in update the CSRF Token.
        if ($jconfig->{csrf_protection} && !$session->param ('logged_in')) {
            my $unique_token = Jarvis::Main::generate_uuid ();
            $session->param ('csrf_token', $unique_token);
        }
        $SIG{__DIE__} = $err_handler;
        if (! $session) {
            die "Error in creating CGI::Session: " . ($! || "Unknown Reason");
        }

        $jconfig->{'session'} = $session;
        $jconfig->{'sname'} = $session->name();
        $jconfig->{'sid'} = $session->id();
        $jconfig->{'sid_param'} = $sid_cookie_name;

        # If the user has specified a Domain or a Path store those values on the Jconfig object.
        # Default the path to /jarvis-agent/
        $jconfig->{'scookie_path'} = (defined $sid_params{'Path'} ? $sid_params{'Path'} : '/');

        # Default the domain to the HTTP_HOST domain this is our best guess. Proxied hosts will require an explicit domain definition.
        $jconfig->{'scookie_domain'} = (defined $sid_params{'Domain'} ? $sid_params{'Domain'} : $ENV{HTTP_HOST});

        # Check if the session cookie transmission should only be completed over HTTPS channels.
        $jconfig->{'scookie_secure'} = (defined $sid_params{'Secure'} ? defined ($Jarvis::Config::yes_value {lc ($sid_params{'Secure'} || "no")}) : 0);

        # CGI::Session does not appear to warn us if the CGI session is file based,
        # and the directory being written to is not writable. Put a check in here to
        # check for a writable session directory (otherwise you end up constantly
        # logging in).
        if ($sid_store =~ /driver:file/ && $sid_params{'Directory'}) {
            if (-e $sid_params{'Directory'}) {
                if (! -w $sid_params{'Directory'}) {
                    die "Webserver user cannot write to CGI::Session directory '$sid_params{'Directory'}'.\n";
                }

            } else {
                if (! mkdir $sid_params{'Directory'}) {
                    die "Webserver user cannot create CGI::Session directory '$sid_params{'Directory'}'.\n";
                }
            }
        }

    } else {
        $jconfig->{'session'} = undef;
        $jconfig->{'sname'} = '';
        $jconfig->{'sid'} = '';
        $jconfig->{'sid_param'} = '';
    }

    # require_post flag. If true, we prohibit username/password as url parameters
    # this is to prevent them from getting logged (e.g. by apache)
    my $login_requires_post = defined ($Jarvis::Config::yes_value {lc ($axml->findvalue ('./login/@require_post') || 'no')});
    # by this stage URL parameters have already been copied into POST parameters
    my $cgi_username = $jconfig->{'cgi'}->param('username');
    my $cgi_password = $jconfig->{'cgi'}->param('password');
    my $url_username = $jconfig->{'cgi'}->url_param('username');
    my $url_password = $jconfig->{'cgi'}->url_param('password');
    my $require_post_error = undef;

    # We might also be given our login details via JSON so we should check if we have some POSTDATA to parse.
    my $cgi_postdata = $jconfig->{'cgi'}->param('POSTDATA');

    # If we get something we should still be careful in case its not JSON encoded. Currently we only support JSON.
    if (defined $cgi_postdata) {
        # Attempt to parse our CGI data as JSON. We'll do this in an EVAL to be safe.
        eval {
            my $parsed_cgi_postdata = decode_json ($cgi_postdata);
            # If we have any of our expected login fields apply them against our existing parameters so we can continue our login.
            $cgi_username = $parsed_cgi_postdata->{username} // $cgi_username;
            $cgi_password = $parsed_cgi_postdata->{password} // $cgi_password;
        }
    }

    if ($login_requires_post and ($url_username or $url_password)) {
        &Jarvis::Error::log ($jconfig, "Username/password provided as URL parameters when require_post was specified (removed).");
        $require_post_error = "username/password provided as URL parameters when require_post was specified";
        $cgi_username = undef;
        $cgi_password = undef;
    }

    # Username can come from a couple of different places.  Normally from CGI,
    # but the ::check method can also be called programmatically with an
    # override username.
    #
    my $offered_username = ($override_href && $$override_href{'username'}) || $cgi_username || '';
    $jconfig->{'offered_username'} = $offered_username;
    $offered_username =~ s/^\s+//;
    $offered_username =~ s/\s+$//;

    # Same with password.
    #
    my $offered_password = ($override_href && $$override_href{'password'}) || $cgi_password || '';
    $offered_password =~ s/^\s+//;
    $offered_password =~ s/\s+$//;

    # By default these values are all empty.  Note that we never allow username
    # and group_list to be undef, too many things depend on it having some value,
    # even if that is just ''.
    #
    my ($error_string, $username, $group_list, $logged_in, $additional_safe, $additional_cookies) = ('', '', '', 0, undef, undef);
    my $already_logged_in = 0;

    my $force_relogin = $override_href && $$override_href{'force_relogin'};
    if ($force_relogin) {
        &Jarvis::Error::debug ($jconfig, "Forcing new login check.  Ignore any existing logged_in session status.");
    }

    # Our login module configuration.
    my $login_module = $axml->findvalue ('./login/@module');

    # Get our login parameter values.
    my %login_parameters = ();
    if ($login_module) {

        if ($axml->exists ('./login/parameter')) {
            foreach my $parameter ($axml->findnodes ('./login/parameter')) {
                &Jarvis::Error::debug ($jconfig, "Login Parameter: " . $parameter->{'name'} . " -> " . $parameter->{'value'});
                $login_parameters {$parameter->{'name'}} = $parameter->{'value'};
            }
        }

        my $lib = $axml->findvalue ('./login/@lib') || undef;

        &Jarvis::Error::debug ($jconfig, "Using default libs: '" . (join ',', @{$jconfig->{'default_libs'}}) . "'". ($lib ? ", plugin lib '$lib'." : ", no plugin specific lib."));
        &Jarvis::Error::debug ($jconfig, "Loading login module '" . $login_module . "'.");
        {
            map { eval "use lib \"$_\""; } @{$jconfig->{'default_libs'}};
            eval "use lib \"$lib\"" if $lib;
            eval "require $login_module";
            if ($@) {
                die "Cannot load login module '$login_module': " . $@;
            }
        }
    }


    # Existing, successful Jarvis session?  Fine, we trust this.
    #
    my $session = $jconfig->{'session'};
    if ($session && $session->param('logged_in') && $session->param('username') && ! $force_relogin) {
        &Jarvis::Error::debug ($jconfig, "Already logged in for session '" . $jconfig->{'sid'} . "'.");

        $logged_in         = $session->param('logged_in') ? 1 : 0;
        $username          = $session->param('username') || '';
        $group_list        = $session->param('group_list') || '';
        $already_logged_in = 1;

        # Copy any additional safe params from session context into $jconfig's area.
        my $dataref = $session->dataref();
        foreach my $name (keys %$dataref) {
            next if ($name !~ m/^__/);
            my $value = $dataref->{$name};
            &Jarvis::Error::debug ($jconfig, "Session set additional safe parameter '$name' = " . ($value ? "'$value'" : "undefined"));
            $jconfig->{'additional_safe'}{$name} = $value;
        }

        # Add to our $args_href since e.g. fetch queries might use them.
        $jconfig->{'logged_in'}    = $logged_in;
        $jconfig->{'username'}     = $username;
        $jconfig->{'error_string'} = $error_string;
        $jconfig->{'group_list'}   = $group_list;

        # If we are logged in check if our login module implements a refresh mechanism. Some external providers utilizing SSO and OAuth expose a refresh endpoint that will
        # Let us refresh the refresh_token we are storing on the session and continue our ongoing session.
        # Not all login modules may implement a refresh method. Lets sanity check using the UNIVERSAL::can method.
        if ($logged_in && $login_module && $login_module->can ('refresh')) {

            my $error_string;
            my $refresh_method = $login_module . "::refresh";
            {
                no strict 'refs';
                ($error_string) = &$refresh_method ($jconfig, %login_parameters);
            }

            # If our refresh method generated any sort of error message we should alert.
            if ($error_string) {
                $jconfig->{'error_string'} = $error_string;
                return 0;
            }
        }

    # No successful session?  Login.  Note that we store failed sessions too.
    #
    # Note that not all actions allow you to provide a username and password for
    # login purposes.  "status" does, and so does "fetch".  But the others don't.
    # For exec scripts that's good, since it means that a report parameter named
    # "username" won't get misinterpreted as an attempt to login.
    #
    } elsif ($login_module) {

        my $login_method = $login_module . "::check";
        {
            no strict 'refs';
            ($error_string, $username, $group_list, $additional_safe, $additional_cookies) = &$login_method ($jconfig, $offered_username, $offered_password, %login_parameters);
            # login is likely to fail if URL username/password are deleted due to require_post
            if ($require_post_error) {
                $error_string = ($error_string ? "$error_string ($require_post_error)" : "Login ok, but $require_post_error");
            }
        }

        (defined $additional_safe) || ($additional_safe = {});
        (defined $additional_cookies) || ($additional_cookies = {});

        $username || ($username = '');
        $group_list || ($group_list = '');
        $logged_in = (($error_string eq "") && ($username ne "")) ? 1 : 0;

        &Jarvis::Error::debug ($jconfig, "Login check complete.  Logged in = $logged_in.  User = $username.");
        if (! $logged_in) {
            &Jarvis::Error::debug ($jconfig, "Not logged in.  Error string = '$error_string'.");
        }

        # Add to our $args_href since e.g. fetch queries might use them.
        $jconfig->{'logged_in'} = $logged_in;
        $jconfig->{'username'} = $username;
        $jconfig->{'error_string'} = $error_string;
        $jconfig->{'group_list'} = $group_list;

        # Invoke our after-login hook.  This can invoke "die" if it wants.  But
        # generally it just gives it the chance to do extra auditing and/or add
        # extra "safe" parameters.
        #
        if ($logged_in) {
            &Jarvis::Hook::after_login ($jconfig, $additional_safe);
        }

        # Check for a group mappings object within the login configuration block. This will map parsed groups to
        # static groups that are configured within the login block.
        # We do this after our after_login hook as those hooks may also modify the group mappings.
        if ($axml->exists ('./login/group_mappings')) {
            if ($axml->exists ('./login/group_mappings/group_mapping')) {

                # Split groups into hash. Preserving the original hash.
                my %initial_groups;
                foreach my $group (split (',', $jconfig->{'group_list'})) {
                    $initial_groups{$group} = 1;
                }

                # Create variable to store our mapped groups separately.
                my %mapped_groups;

                # Attempt to process each available group mapping.
                foreach my $group_mapping ($axml->findnodes ('./login/group_mappings/group_mapping')) {
                    # Parse parameters and check both are provided and are defined.
                    $group_mapping->exists ('./@from') || die ("Group mapping must have from mapping.");
                    my $from_group = $group_mapping->findvalue ('./@from');
                    length ($from_group) || die ("Group mapping must have from mapping.");

                    $group_mapping->exists ('./@to') || die ("Group mapping must have to mapping.");
                    my $to_group = $group_mapping->findvalue ('./@to');
                    length ($to_group) || die ("Group mapping must have to mapping.");

                    # If the from group is present in the group list returned by the login module add the mapped to group to it.
                    if ($initial_groups{$from_group}) {
                        $mapped_groups{$to_group} = 1;
                    }
                }
                # After processing re-merge the parsed groups.
                my %merged_groups = (%initial_groups, %mapped_groups);
                $jconfig->{'group_list'} = join (',', sort (keys (%merged_groups)));
            }
        }

        # If Jarvis is maintaining its own session (and it usually is) then track
        # these parameters for future requests also.  Note that the hook may have
        # modified them in jconfig.
        #
        if ($session) {
            $session->param('logged_in', $jconfig->{'logged_in'});
            $session->param('username', $jconfig->{'username'});
            $session->param('group_list', $jconfig->{'group_list'});
        }

        # Do we have any additional safe parameters returned by the login module?
        # These must begin with "__" because they are safe params.
        #
        # Set them in our jconfig, and also put them in the session to be saved
        # for next time (if we have a session, which we usually do).
        #
        foreach my $name (keys %$additional_safe) {
            ($name =~ m/^__/) || die "Invalid additional safe parameter name '$name' returned by login module.\n";
            my $value = $additional_safe->{$name};
            &Jarvis::Error::debug ($jconfig, "Login module and/or plugin returned additional safe param '$name'.");

            $jconfig->{'additional_safe'}{$name} = $value;
            $session && $session->param($name, $value);
        }

    # Login module is actually optional.  Some applications just don't do login.
    } else {
        &Jarvis::Error::debug ($jconfig, "Application has no defined login module.");
        $jconfig->{'logged_in'} = 0;
        $jconfig->{'username'} = "";
        $jconfig->{'error_string'} = "No Login Module Configured";
        $jconfig->{'group_list'} = "";
    }


    # Set/extend session expiry.  Flush new/modified session data.
    if ($session) {
        my $session_expiry = $jconfig->{'expiry'} || $axml->findvalue ('./sessiondb/@expiry') || '+1h';
        $session->expire ($session_expiry);
        $session->flush ();

        # If we arent logged in dont send the user a session.
        if ($jconfig->{logged_in}) {

            # Store the new cookie in the context, whoever returns the result should return this.
            #
            # We only send the cookie back to the user if the source of our sid was a cookie.
            # This ensures that we don't trample a pre-existing cookie if the sid came from
            # a URL.
            #
            # This in turn allows us to have both a cookie based session alongside one or more
            # url based sessions. We get the best of both worlds.
            #
            if (!$jconfig->{'sid_source'} || $jconfig->{'sid_source'} eq 'cookie') {

                my $cookies = [ CGI::Cookie->new (
                    -name => $jconfig->{'sname'},
                    -value => $jconfig->{'sid'},
                    -HttpOnly => 1,
                    -Path => $jconfig->{'scookie_path'},
                    -secure => $jconfig->{'scookie_secure'},
                    -samesite => 'Strict'   # Note - only supported on 4.29 of CGI::Cookie or later
                )];

                $jconfig->{'cookie'} = $cookies;

                # If there were additional cookies specified by a Login Module then add those as well.
                if (defined $additional_cookies && ref($additional_cookies) eq 'HASH') {
                    foreach my $key (keys %{$additional_cookies}) {
                        push(@$cookies, CGI::Cookie->new(
                            -name => $key,
                            -value => $additional_cookies->{$key},
                            -HttpOnly => 1,
                            -Path => $jconfig->{'scookie_path'},
                            -secure => $jconfig->{'scookie_secure'},
                            -samesite => 'Strict'   # Note - only supported on 4.29 of CGI::Cookie or later
                        ))
                    }
                }

                # If we have CSRF Protection enabled our session will store a CSRF token. We need to send it to our client
                # so that they can include it in the headers for subsequent requests.
                if ($jconfig->{csrf_protection}) {
                    # Add Cross Site Request Forgery token cookie.
                    # Path must be '/' as we are not making a Jarvis request to validate cross site protection.
                    # Also not just "HttpOnly" as javascript needs access to this Cookie.
                    push(@$cookies, CGI::Cookie->new(
                        -name => $jconfig->{csrf_cookie},
                        -value => $jconfig->{session}->param ('csrf_token'),
                        -Path => '/',           # Note, left as / as many clients use differing URLs to access applications, and apps are from /
                        -secure => $jconfig->{'scookie_secure'},
                        -samesite => 'Strict'   # Note - only supported on 4.29 of CGI::Cookie or later
                    ));
                }
            }
        }
    }

    # Log the results if we actually tried to login.  Write to tracker database too
    # if we are configured to do so.
    #
    if (! $already_logged_in) {
        my $sid = $session ? ("'" . $jconfig->{'sid'} . "'") : "NO JARVIS SESSION";
        if ($logged_in) {
            &Jarvis::Error::debug ($jconfig, "Login for '$username ($group_list)' on sid $sid.");

        } elsif ($offered_username) {
            &Jarvis::Error::log ($jconfig, "Login fail for '$offered_username' on sid $sid: $error_string.");
        }
    }

    return 1;
}

################################################################################
# Update stored session variables.
#
# Params:
#       jconfig   - Jasper::Config object
#           READ
#               session
#
#       new_vars - Hash of session variables to set/update.
#
# Returns:
#       1 on success.
#       0 if no session is currently active.
################################################################################
#
sub alter_session {
    my ($jconfig, $new_vars) = @_;

    &Jarvis::Error::debug ($jconfig, "Updating session variables.");

    my $axml = $jconfig->{'xml'}->find ('./jarvis/app')->pop ();
    (defined $axml) || die "Cannot find <jarvis><app> in '" . $jconfig->{'app_name'} . ".xml'!\n";

    if (! $axml->exists ('./sessiondb')) {
        &Jarvis::Error::debug ($jconfig, "No session DB is defined.");
        return 0;
    }

    # Where are our sessions stored?
    my $sid_store = $axml->findvalue ('./sessiondb/@store') || "driver:file;serializer:default;id:md5";
    &Jarvis::Error::debug ($jconfig, "SID Store '$sid_store'.");

    my $default_cookie_name = uc ($jconfig->{'app_name'}) . "_CGISESSID";
    my $sid_cookie_name = $axml->findvalue ('./sessiondb/@cookie') || $default_cookie_name;
    CGI::Session->name($sid_cookie_name);
    &Jarvis::Error::debug ($jconfig, "SID Cookie Name '$sid_cookie_name'.");

    my %sid_params = ();
    if ($axml->exists ('./sessiondb/parameter')) {
        foreach my $sid_param ($axml->findnodes ('./sessiondb/parameter')) {
            $sid_params {$sid_param->{'name'}} = $sid_param->{'value'};
        }
    }

    # Find the session ID. Look up the source options configured.
    # by default look only in the cookie.
    #
    # To trigger a new login overriding any cookie that may exist
    # (if configured to look up cookies), configure the order as 'url,cookie'
    # and send a URL with the relevant parameter, but empty.
    my @sid_sources = map { lc (&trim($_)) } split (',', ($axml->findvalue ('./sessiondb/@sid_source') || "cookie"));
    my $sid = undef;
    foreach my $source (@sid_sources) {
        $sid = $jconfig->{'cgi'}->param ($sid_cookie_name) if $source eq 'url';
        $sid = $jconfig->{'cgi'}->cookie ($sid_cookie_name) if $source eq 'cookie';
        if (defined $sid) {
            $jconfig->{'sid_source'} = $source;
            last;
        }
    }
    &Jarvis::Error::debug ($jconfig, "SID source: " . ($jconfig->{'sid_source'} || "none"));

    # If we have no existing session ID, then we cannot alter the session.
    if (! $sid) {
        &Jarvis::Error::debug ($jconfig, "There is no SID for this session.");
        return 0;
    }

    # Get an existing session.
    # Under windows, avoid having CGI::Session throw the error:
    # 'Your vendor has not defined Fcntl macro O_NOFOLLOW, used at C:/Perl/site/lib/CGI/Session/Driver/file.pm line 26.'
    # by hiding the signal handler.

    my $err_handler = $SIG{__DIE__};
    $SIG{__DIE__} = sub {};
    my $session = new CGI::Session ($sid_store, $sid, \%sid_params);
    $SIG{__DIE__} = $err_handler;
    if (! $session) {
        die "Error in creating CGI::Session: " . ($! || "Unknown Reason");
    }

    # Now modify the session vars.
    my $dataref = $session->dataref();
    foreach my $name (keys %$new_vars) {
        my $value = $new_vars->{$name};
        &Jarvis::Error::debug ($jconfig, "Session modified parameter '$name' = " . ($value ? "'$value'" : "undefined"));
        $dataref->{$name} = $value;

        if ($name =~ m/^__/) {
            &Jarvis::Error::debug ($jconfig, "Updated safe parameter '$name' = " . ($value ? "'$value'" : "undefined"));
            $jconfig->{'additional_safe'}{$name} = $value;
        }
    }

    # Write to the session file.
    my $session_expiry = $jconfig->{'expiry'} || $axml->findvalue ('./sessiondb/@expiry') || '+1h';
    $session->expire ($session_expiry);
    $session->flush ();
}

################################################################################
# Logout by deleting the session.
#
# Params:
#       jconfig   - Jasper::Config object
#           READ
#               session
#
#           WRITE
#               session
#               sid
#               sname
#               logged_in
#               username
#               group_list
#               error_string
#
# Returns:
#       "" on success.
#       "<Failure description message>" on failure.
################################################################################
#
sub logout {
    my ($jconfig) = @_;

    my $username = $jconfig->{'username'} || '';
    my $sid = $jconfig->{'sid'} || '';

    &Jarvis::Error::debug ($jconfig, "Logout for '$username' on '$sid'.");
    my $session = $jconfig->{'session'};
    if ($session) {

        # If we have a login module it may implement additional processing that we might want to perform before we clear our session.
        # An example of this might be an OAuth or SSO based module that needs to invalidate an external token.
        # Get our jarvis config and check for a defined custom login module.
        my $axml = $jconfig->{'xml'}->find ('./jarvis/app')->pop ();
        (defined $axml) || die "Cannot find <jarvis><app> in '" . $jconfig->{'app_name'} . ".xml'!\n";
        my $login_module = $axml->findvalue ('./login/@module');

        if ($login_module && $jconfig->{logged_in}) {

            # Get our login parameter values.
            my %login_parameters = ();
            if ($axml->exists ('./login/parameter')) {
                foreach my $parameter ($axml->findnodes ('./login/parameter')) {
                    &Jarvis::Error::debug ($jconfig, "Login Parameter: " . $parameter->{'name'} . " -> " . $parameter->{'value'});
                    $login_parameters {$parameter->{'name'}} = $parameter->{'value'};
                }
            }

            my $lib = $axml->findvalue ('./login/@lib') || undef;

            &Jarvis::Error::debug ($jconfig, "Using default libs: '" . (join ',', @{$jconfig->{'default_libs'}}) . "'". ($lib ? ", plugin lib '$lib'." : ", no plugin specific lib."));
            &Jarvis::Error::debug ($jconfig, "Loading login module '" . $login_module . "'.");
            {
                map { eval "use lib \"$_\""; } @{$jconfig->{'default_libs'}};
                eval "use lib \"$lib\"" if $lib;
                eval "require $login_module";
                if ($@) {
                    die "Cannot load login module '$login_module': " . $@;
                }
            }

            # Not all login modules may implement a logout method. Lets sanity check using the UNIVERSAL::can method.
            if ($login_module->can ('logout')) {

                my $error_string;
                my $logout_method = $login_module . "::logout";
                {
                    no strict 'refs';
                    ($error_string) = &$logout_method ($jconfig, %login_parameters);
                }

                # If our logout module generated any sort of error message we should alert the fact and halt the logout.
                if ($error_string) {
                    $jconfig->{'error_string'} = $error_string;
                    return 0;
                }
            }
        }

        &Jarvis::Hook::before_logout ($jconfig);

        $jconfig->{'session'} = undef;
        $jconfig->{'sname'} = '';
        $jconfig->{'sid'} = '';
        if ($jconfig->{'logged_in'}) {
            $jconfig->{'logged_in'} = 0;
            $jconfig->{'error_string'} = "Logged out at client request.";
            $jconfig->{'username'} = '';
            $jconfig->{'group_list'} = '';

        } else {
            $jconfig->{'error_string'} = "Logout not required (no existing session).";
        }

        $session->delete();
        $session->flush();

    } else {
        &Jarvis::Error::debug ($jconfig, "Jarvis has no session information.  Cannot logout.");
    }

    return 1;
}

################################################################################
# Checks that a given group list grants access to the currently logged in user
# or the current public (non-logged-in) user.  All this permission check is
# currently performed by group matching.  We don't provide any way to control
# access for individual users within a group.
#
#    ""   -> Allow nobody at all.
#    "**" -> Allow all and sundry.
#    "*"  -> Allow all logged-in users.
#    "group,[group]"  -> Allow those in one (or more) of the named groups.
#
# Params:
#       jconfig   - Jasper::Config object
#           READ
#               logged_in
#               username
#               group_list
#
#       $allowed_groups - List of permitted groups or "*" or "**"
#
# Returns:
#       "" on success.
#       "<Failure description message>" on failure.
################################################################################
#
sub check_access {
    my ($jconfig, $allowed_groups) = @_;

    # Check permissions
    if ($allowed_groups eq "") {
        return "Resource has no access.";

    # Allow access to all even those not logged in.
    } elsif ($allowed_groups eq "**") {
        return "";

    # Allow access to any logged in user.
    } elsif ($allowed_groups eq "*") {
        $jconfig->{'logged_in'} || return "Login required.";

    # Allow access to a specific comma-separated group list.
    } else {
        # If we're not logged in, then we can't access this either.
        $jconfig->{'logged_in'} || return "Login required.";

        # Let's see if we belong to any of the groups.
        my $allowed = 0;
        foreach my $allowed_group (split (',', $allowed_groups)) {
            foreach my $member_group (split (',', $jconfig->{'group_list'})) {
                if ($allowed_group eq $member_group) {
                    $allowed = 1;
                    last;
                }
            }
            last if $allowed;
        }
        $allowed || return "Not in a permitted group.";
    }
    return "";
}

1;

