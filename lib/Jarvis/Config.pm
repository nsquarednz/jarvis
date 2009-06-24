###############################################################################
# Description:  The Config::Setup method will read variables from our
#               <app_name>.xml (and possibly other sources).  It will perform
#               a Login attempt if required, and will set other variables
#               based on the results of the Login.  The derived config is
#               stored in an %args hash so that other functions can access
#               it.
#
#               The actual login functionality is contained in a login module,
#               e.g. Database, None, LDAP, etc.  The <app_name>.xml tells this
#               Config function which module to use for this application.
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
use DBI;
use XML::Smart;

package Jarvis::Config;

use Jarvis::Error;

%Jarvis::Config::yes_value = ('yes' => 1, 'true' => 1, 'on' => 1, '1' => 1);

################################################################################
# Setup our entire jarvis config, based on the application name provided, which
# directs us to our application xml file.
#
# Params:
#       $app_name   - MANDATORY arg
#       %args       - Hash of optional args.
#           $args{'cgi'}                CGI object.  We will use new CGI; by defaul.
#           $args{'etc_dir'}            We will use "<cgi-bin>/../etc" by default.
#
# Returns:
#       Jarvis::Config object
#           WRITE
#               app_name           Copy of app name provided to us.
#               xml                Handle to an XML::Smart object of app config.
#               cgi                Handle to a CGI object for this request.
#               format             Format xml or json?
#               debug              Debug enabled for this app?
################################################################################
#
sub new {
    my ($class, $app_name, %args) = @_;

    my $self = {};
    bless $self, 'Jarvis::Config';

    # Check our parameters for correctness.  Note that jarvis.pl has already
    # validated this, but other callers might not have, so we re-validate.
    #
    $self->{'app_name'} = $app_name || die "Missing parameter 'app_name'\n";
    ($self->{'app_name'} =~ m/^[\w\-]+$/) || die "Invalid characters in parameter 'app_name'.\n";

    # We'll need a CGI handle.
    $self->{'cgi'} = $args{'cgi'} || new CGI;

    # Directory for a bunch of later config.
    $self->{'etc_dir'} = $args{'etc_dir'} || "../etc" || die "Missing parameter 'etc_dir'\n";
    (-d $self->{'etc_dir'}) || die "Parameter 'etc_dir' does not specify a directory.\n";

    ###############################################################################
    # Load our global configuration.
    ###############################################################################
    #
    # Process the global XML config file.
    my $xml_filename = $self->{'etc_dir'} . "/" . $self->{'app_name'} . ".xml";
    my $xml = XML::Smart->new ("$xml_filename") || die "Cannot read '$xml_filename': $!.";
    ($xml->{jarvis}) || die "Missing <jarvis> tag in '$xml_filename'!\n";

    $self->{'xml'} = $xml;

    ###############################################################################
    # Get the application config.  Note that we must NOT store this in our args
    # hashref because XML::Smart->DESTROY gets confused if it attempts to clean up
    # XML::Smart objects at different points in the tree.
    #
    # This function should fetch all the application config at one time.
    ###############################################################################
    #
    # We MUST have an entry for this application in our config.
    my $axml = $xml->{jarvis}{app};
    (defined $axml) || die "Cannot find <jarvis><app> in '" . $self->{'app_name'} . ".xml'!\n";

    # This is used by all sorts of debug methods.  Very important.
    $self->{'debug'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'debug'}->content || "no")});

    # This is used by several things, so let's store it in our config.
    $self->{'format'} = lc ($self->{'cgi'}->param ('format') || $axml->{'format'}->content || "json");

    # This is an optional METHOD overide parameter, similar to Ruby on Rails.
    # It bypasses a problem where non-proxied Flex can only send GET/POST requests.
    $self->{'method_param'} = $self->{'cgi'}->param ('method_param') || "_method";

    return $self;
}

################################################################################
# Go through the list of user-supplied variables and decide which ones are
# safe.
#
# Then add some special variables.
#
# Any variable which starts with "__" is safe.  Specifically.
#
#   __username  -> <logged-in-username>
#   __grouplist -> ('<group1>', '<group2>', ...)
#   __group:<groupname>  ->  1 (iff belong to <groupname>) or NULL
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               username
#               group_list
#
#       $raw_params_href - User-supplied (unsafe) hash of variables.
#
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       1
################################################################################
#
sub safe_variables {

    my ($jconfig, $raw_params_href, $rest_args_aref, $rest_arg_prefix) = @_;

    my %safe_params = ();
    $rest_arg_prefix = $rest_arg_prefix || '';

    # First set the default parameters configured in the config file.
    my $pxml = $jconfig->{'xml'}{'jarvis'}{'app'}{'default_parameters'};
    if ($pxml && $pxml->{'parameter'}) {
        foreach my $parameter ($pxml->{'parameter'}('@')) {
            &Jarvis::Error::debug ($jconfig, "Default Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
            $safe_params {$parameter->{'name'}->content} = $parameter->{'value'}->content;
        }
    }

    # Copy through the SAFE user-provided parameters.  One leading underscore
    # is permitted, but never TWO leading underscores.  No special characters.
    foreach my $name (keys %$raw_params_href) {
        if ($name =~ m/^_?[a-z][a-z0-9_\-]*$/i) {
            &Jarvis::Error::debug ($jconfig, "User Parameter: $name -> " . $$raw_params_href {$name});
            $safe_params{$name} = $$raw_params_href {$name};
        }
    }

    # And our REST args go through as variable "1", "2", etc...
    foreach my $i (0 .. $#$rest_args_aref) {
        my $name = $rest_arg_prefix . ($i + 1);
        my $value = $$rest_args_aref[$i];

        &Jarvis::Error::debug ($jconfig, "Rest Arg: $name -> $value");
        $safe_params{$name} = $value;
    }

    # Our secure variables.  Note that __username and __group_list are null if
    # the user hasn't logged in
    #
    $safe_params{"__username"} = $jconfig->{'username'};
    $safe_params{"__group_list"} = $jconfig->{'group_list'};
    &Jarvis::Error::debug ($jconfig, "Username: __username = " . $safe_params{"__username"});
    &Jarvis::Error::debug ($jconfig, "Group List: __group_list = " . $safe_params{"__group_list"});

    # And our separate groups.
    foreach my $group (split (',', $jconfig->{'group_list'})) {
        $safe_params{"__group:$group"} = 1;
        &Jarvis::Error::debug ($jconfig, "Group: __group:$group = 1");
    }


    return %safe_params;
}

1;