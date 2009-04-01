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

my %yes_value = ('yes' => 1, 'true' => 1, '1' => 1);

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
#           $self->{'format'}             Format xml or json?
#           $self->{'use_placeholders'}   Does this app use placeholders for SQL substitution?
#           $self->{'debug'}              Debug enabled for this app?
#           $self->{'max_rows'}           Value for {{max_rows}}
#           $self->{'dbconnect'}          Database connection string
#           $self->{'dbuser'}             Database username
#           $self->{'dbpass'}             Database password
#           $self->{'dataset_dir'}        Our dataset directory for this application.
#           $self->{'exec'}               Optional hash of exec <action-name> to additional parameters:
#               -> {'command'}              Shell command to run.
#               -> {'add_headers'}          0/1 should we add headers, or will script do it?
#               -> {'filename_arg'}         A special input parameter we should use as filename.
################################################################################
#
sub new {
    my ($class, $app_name, %args) = @_;

    my $self = {};
    bless $self, 'Jarvis::Config'; 

    # Check our parameters for correctness.
    $self->{'app_name'} = $app_name || die "Missing parameter 'app_name'\n";
    ($self->{'app_name'} =~ m/^\w+$/) || die "Invalid characters in parameter 'app_name'.\n";

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
    my $xml = XML::Smart->new ("$xml_filename") || die "Cannot read '$xml_filename': $!\n";
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

    # And this MUST contain our dataset dir.
    my $dataset_dir = $axml->{'dataset_dir'}->content || die "No attribute 'dataset_dir' defined for <app> in '" . $self->{'app_name'} . ".xml'!\n";
    $self->{'dataset_dir'} = $dataset_dir;
    &Jarvis::Error::Debug ($self, "Dataset Directory '$dataset_dir'.");


    ###############################################################################
    # See if we have any extra "exec" actions for this application.
    ###############################################################################
    #
    my %execs = ();
    if ($axml->{'exec'}) {
        foreach my $exec (@{ $axml->{'exec'} }) {
            my $action = $exec->{'action'}->content;

            $action || die "No attribute 'action' designed for <app><exec> in '" . $self->{'app_name'} . ".xml'!\n";
            $exec->{'access'}->content || die "No attribute 'access' designed for <app><exec> in '" . $self->{'app_name'} . ".xml'!\n";
            $exec->{'command'}->content || die "No attribute 'command' designed for <app><exec> in '" . $self->{'app_name'} . ".xml'!\n";

            $execs {$action}{'access'} = $exec->{'access'}->content;
            $execs {$action}{'command'} = $exec->{'command'}->content;
            $execs {$action}{'add_headers'} = defined ($yes_value {lc ($exec->{'add_headers'}->content || "no")});
            $execs {$action}{'filename_parameter'} = $exec->{'filename_parameter'}->content;

            &Jarvis::Error::Debug ($self, "Installed custom <exec> action '$action'.");
        }
    }
    $self->{'exec'} = \%execs;

    ###############################################################################
    # Determine some other application flags.
    ###############################################################################
    #
    $self->{'format'} = lc ($self->{'cgi'}->param ('format') || $axml->{'format'}->content || "json");
    (($self->{'format'} eq "json") || ($self->{'format'} eq "xml")) || die "Unsupported format '$self->{'format'}'!\n";

    $self->{'use_placeholders'} = defined ($yes_value {lc ($axml->{'use_placeholders'}->content || "no")});
    $self->{'debug'} = defined ($yes_value {lc ($axml->{'debug'}->content || "no")});
    $self->{'max_rows'} = lc ($axml->{'max_rows'}->content || 200);

    ###############################################################################
    # Connect to the database.  We'd love to cache these connections.  Need to
    # do this early, since the login module can check logins against DB table.
    ###############################################################################
    #
    my $dbxml = $axml->{'database'};
    if ($dbxml) {
        $self->{'dbconnect'} = $dbxml->{'connect'}->content || "dbi:Pg:" . $self->{'app_name'};
        $self->{'dbusername'} = $dbxml->{'username'}->content;
        $self->{'dbpassword'} = $dbxml->{'password'}->content;
    }

    return $self;
}

1;