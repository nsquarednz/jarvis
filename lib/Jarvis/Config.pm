###############################################################################
# Description:  Functions for creating dojo helper JS for grid widgets.
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

use Carp;
use CGI;
use CGI::Session;
use DBI;
use XML::Smart;

use lib "/opt/jarvis/lib";

package Jarvis::Config;

my %yes_value = ('yes' => 1, 'true' => 1, '1' => 1);

################################################################################
# Setup our entire jarvis config, based on the root directory passed in.
#
# Params:
#       $args_href - Reference to our args. 
#
#   You Must SPECIFY
#           $args{'cgi'}                CGI object as passed in.
#           $args{'app_name'}           App name as passed in.
#           $args{'config_dir'}         "$java_root/config" used by Dataset.pm etc.
#
#   We will ADD
#           $args{'format'}             Format xml or json?
#           $args{'use_placeholders'}   Does this app use placeholders for SQL substitution?
#           $args{'debug'}              Debug enabled for this app?
#           $args{'max_rows'}           Value for {{max_rows}}
#           $args{'dbh'}                Database handle
#           $args{'sname'}              Session name for/from cookie.
#           $args{'sid'}                Session ID for/from cookie.
#           $args{'logged_in'}          Did a user login?
#           $args{'user_name'}          Which user logged in?
#           $args{'error_string'}       What error if not logged in?
#           $args{'group_list'}         Comma-separated group list.
#
# Returns:
#       1
################################################################################
#
sub Setup {
    my ($args_href) = @_;

    # Check our mandatory params
    $$args_href{'cgi'} || die "Missing parameter 'cgi'\n";
    $$args_href{'app_name'} || die "Missing parameter 'app_name'\n";
    $$args_href{'config_dir'} || die "Missing parameter 'config_dir'\n";

    # Check our parameters for correctness. 
    ($$args_href{'app_name'} =~ m/^\w+$/) || die "Invalid characters in parameter 'app_name'.\n";
    (-d $$args_href{'config_dir'}) || die "Parameter 'config_dir' does not specify a directory.\n";

    ###############################################################################
    # Load our global configuration.
    ###############################################################################
    #
    # Process the global XML config file.
    my $gxml_filename = $$args_href{'config_dir'} . "/global.xml";
    my $gxml = XML::Smart->new ("$gxml_filename") || die "Cannot read '$gxml_filename': $!\n";
    ($gxml->{jarvis}) || die "Missing <jarvis> tag in '$gxml_filename'!\n";

    ###############################################################################
    # Get the application config.  Note that we must NOT store this in our args
    # hashref because XML::Smart->DESTROY gets confused if it attempts to clean up
    # XML::Smart objects at different points in the tree.
    #
    # This function should fetch all the application config at one time.
    ###############################################################################
    #
    # We MUST have an entry for this application in our config.
    my $axml = (grep { $_->{name} eq $$args_href{'app_name'} } @{$gxml->{jarvis}{app}}) [0];
    (defined $axml) || die "Application '" . $$args_href{'app_name'} . "' not defined in default.xml!\n";

    ###############################################################################
    # Determine some other application flags.
    ###############################################################################
    # 
    $$args_href{'format'} = lc ($$args_href{'cgi'}->param ('format') || $axml->{'format'}->content || "json");
    (($$args_href{'format'} eq "json") || ($$args_href{'format'} eq "xml")) || die "Unsupported format '$$args_href{'format'}'!\n";

    $$args_href{'use_placeholders'} = defined ($yes_value {lc ($axml->{'use_placeholders'}->content || "no")});
    $$args_href{'debug'} = defined ($yes_value {lc ($axml->{'debug'}->content || "no")});
    $$args_href{'max_rows'} = lc ($axml->{'max_rows'}->content || 200);

    ###############################################################################
    # Connect to the database.  We'd love to cache these connections.  Need to
    # do this early, since the login module can check logins against DB table.
    ###############################################################################
    #
    my $dbxml = $axml->{database};
    my $dbconnect = $dbxml->{connect}->content || "dbi:Pg:" . $$args_href{'app_name'};
    my $dbuser = $dbxml->{username}->content;
    my $dbpass = $dbxml->{password}->content;

    $$args_href{'dbh'} = DBI->connect($dbconnect, $dbuser, $dbpass) or die DBI::errstr;

    ###############################################################################
    # Login Process.  Happens after DB, 'cos login info can be in DB.
    ###############################################################################
    #
    my $login_module = $axml->{login}{module} || die "Application '" . $$args_href{'app_name'} . "' has no defined login module.\n";

    eval "require $login_module";
    if ($@) {
        die "Cannot load login module '$login_module': " . $@;
    }

    # Where are our sessions stored?
    my $sid_store = $axml->{'sessiondb'}->{'store'}->content || "driver:file;serializer:default;id:md5";
    &Jarvis::Error::Debug ("SID Store '$sid_store'.", %$args_href);

    my %sid_params = ();
    foreach my $sid_param (@{ $axml->{'sessiondb'}->{'parameter'} }) {
        $sid_params {$sid_param->{'name'}} = $sid_param->{'value'};
    }

    # Get an existing/new session.
    my $session = new CGI::Session ($sid_store, $$args_href{'cgi'}, \%sid_params);
    $$args_href{'sname'} = $session->name();
    $$args_href{'sid'} = $session->id();

    # See if we already logged in.
    my ($error_string, $user_name, $group_list, $logged_in) = ('', undef, undef, 0);

    # Existing, successful session?  Fine, we trust this.
    if ($session->param('logged_in') && $session->param('user_name')) {
        &Jarvis::Error::Debug ("Already logged in for session '" . $$args_href{'sid'} . "'.", %$args_href);
        $logged_in = $session->param('logged_in');
        $user_name = $session->param('user_name');
        $group_list = $session->param('group_list');

    # No successful session?  Login.  Note that we store failed sessions too.
    } else {
        &Jarvis::Error::Debug ("Login attempt on '" . $$args_href{'sid'} . "'.", %$args_href);

        # Get our login parameter values.  We were using $axml->{login}{parameter}('[@]', 'name');
        # but that seemed to cause all sorts of DataDumper and cleanup problems.  This seems to
        # work smoothly.
        my %login_parameters = ();
        foreach my $parameter ($axml->{login}{parameter}('@')) {
            &Jarvis::Error::Debug ("Login Parameter: " . $parameter->{'name'} . " -> " . $parameter->{'value'}, %$args_href);
            $login_parameters {$parameter->{'name'}->content} = $parameter->{'value'}->content;
        }

        ($error_string, $user_name, $group_list) = &Jarvis::Login::Check (\%login_parameters, $args_href);

        $logged_in = (($error_string eq "") && ($user_name ne "")) ? 1 : 0;
        $session->param('logged_in', $logged_in);
        $session->param('user_name', $user_name);
        $session->param('group_list', $group_list);
    }

    $logged_in || &Jarvis::Error::Log ("Login fail: $error_string", %$args_href);

    # Give another 1 hour login.  Flush new/modified session data.
    $session->expire('+1h');
    $session->flush();

    # Add to our $args_href since e.g. fetch queries might use them.
    $$args_href{'logged_in'} = $logged_in;
    $$args_href{'user_name'} = $user_name;
    $$args_href{'error_string'} = $error_string;
    $$args_href{'group_list'} = $group_list;

    return 1;
}

1;