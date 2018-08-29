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

package Jarvis::Config;

use CGI;
use CGI::Session;
use DBI;
use XML::Smart;

use Jarvis::Error;
use Data::Dumper;

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
#               retain_null        Retain nulls when outputting JSON?
#               debug              Debug enabled for this app?
#               dump               Dump (Detailed Debug) enabled for this app?
#               log_format         Format for log and debug output.
#               error_response_format         
#                                  The format of error messages sent to the client
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

    # We also store the mod_perl IO object, if we get it
    $self->{'mod_perl_io'} = $args{'mod_perl_io'} || undef;

    # Directory for a bunch of later config.
    $self->{'etc_dir'} = $args{'etc_dir'} || "../etc" || die "Missing parameter 'etc_dir'\n";
    (-d $self->{'etc_dir'}) || die "Parameter 'etc_dir' does not specify a directory.\n";

    # Setup http headers
    $self->{'http_headers'} = {};

    ###############################################################################
    # Load our global configuration.
    ###############################################################################
    #
    # Process the global XML config file.
    my $xml_filename = $self->{'etc_dir'} . "/" . $self->{'app_name'} . ".xml";
    my $xml = XML::Smart->new ("$xml_filename") || die "Cannot read '$xml_filename': $!.\n";
    ($xml->{jarvis}) || die "Missing <jarvis> tag in '$xml_filename'!\n";

    $self->{'xml'} = $xml;

    ###############################################################################
    # Get any included files that will contain extra config
    # These files are parsed into the same XML object
    # Example icluded file
    #<?xml version="1.0" encoding="utf-8"?>
    # <jarvis>
    #     <app>
    #         <routes>
    #             <route path="/api/office" dataset="Franchise"/>
    #         </routes>
    #
    #         <plugin dataset="TEST" access="*" module="Boris::TEST" add_headers="yes"/>
    #     </app>
    #</jarvis>
    #
    # Example include in the jarvis config xml
    #   <?xml version="1.0" encoding="utf-8"?>
    #       <jarvis>
    #
    #           <include file="/home/dwalmsley/dev/porse/boris-angular.hg/etc/routes.xml"/>
    #           ....
    #
    ###############################################################################
    #
    #Loop through all the include directives read the files and merge them at the top
    #level back into the app xml so the rest of the config processing will include items
    #from these files.
    foreach my $include ($xml->{jarvis}{include}('@') ) {
        my $filename = $include->{'file'}->content || die "Bad include filename!: $!.";
        my $subXml = XML::Smart->new ($filename) || die "Cannot read '$filename': $!.";

        #note we only merge in at the level of nodes directly below app.
        foreach my $nodeName ($subXml->{jarvis}{app}->nodes_keys()){
            $xml->{jarvis}{app}{$nodeName} = $subXml->{jarvis}{app}{$nodeName}->tree_pointer();
        }
    }


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

    # Defines if we should produce debug and/or dump output.  Dump implies debug.
    $self->{'dump'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'dump'}->content || "no")});
    $self->{'debug'} = $self->{'dump'} || defined ($Jarvis::Config::yes_value {lc ($axml->{'debug'}->content || "no")});

    # Set binmode on STDERR because folks could want to send us UTF-8 content, and
    # debug (or even log) could raise "Wide character in print" errors.
    binmode STDERR, ":utf8";

    # This is used by both debug and log output.
    $self->{'log_format'} = $axml->{'log_format'}->content || '[%P/%A/%U/%D][%R] %M';

    # This is what format we use when sending death messages back to the client
    $self->{'error_response_format'} = $axml->{'error_response_format'}->content || '[%T][%R] %M';

    # This is used by several things, so let's store it in our config.
    $self->{'format'} = lc ($self->{'cgi'}->param ('format') || $axml->{'format'}->content || "json");

    # This is used to toggle on and off the ability to return nulls, default is off.
    $self->{'retain_null'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'retain_null'}->content || "no")});

    # This is an optional METHOD overide parameter, similar to Ruby on Rails.
    # It bypasses a problem where non-proxied Flex can only send GET/POST requests.
    $self->{'method_param'} = $self->{'cgi'}->param ('method_param') || "_method";

    # Load settings for CSRF protection. Enabled flag, cookie name and header name.
    $self->{'csrf_protection'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'csrf_protection'}->content || "no")});
    $self->{'csrf_cookie'} = uc ($axml->{'csrf_cookie'}->content || "XSRF-TOKEN");
    $self->{'csrf_header'} = uc ($axml->{'csrf_header'}->content || "X-XSRF-TOKEN");

    # Check if cross origin protection is enabled. All incoming requests will have their referer or origin compared to the host configuration.
    $self->{'cross_origin_protection'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'cross_origin_protection'}->content || "no")});

    # Check if XSRF protection is enabled. All JSON requests will be prefixed with ")]}',\n"
    $self->{'xsrf_protection'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'xsrf_protection'}->content || "no")});

    # Pull out the list of default (Perl) library paths to use for perl plugins scripts
    # from the configuration, and store in an array in the config item.
    $self->{'default_libs'} = [];
    if ($axml->{'default_libs'}{'lib'}) {
        foreach my $lib ($axml->{'default_libs'}{'lib'}('@')) {
            &Jarvis::Error::debug ($self, "Default Lib Path: " . ($lib->{'path'}->content || 'UNDEFINED'));
            if ($lib->{'path'}->content) {
                push (@{ $self->{'default_libs'} }, $lib->{'path'}->content);
            }
        }
    }


    # Basic security check here.
    $self->{'require_https'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'require_https'}->content || "no")});
    if ($self->{'require_https'} && ! $self->{'cgi'}->https()) {
        die "Client must access over HTTPS for this application.\n";
    }

    ###############################################################################
    # Create a placeholder for a hash of ADDITIONAL safe parameters.  These are
    # intended for additional information, e.g. extended login returned results.
    ###############################################################################
    my %additional_safe = ();
    $self->{'additional_safe'} = \%additional_safe;

    return $self;
}


################################################################################
# Returns a list of our default parameters.  Could be handy to some.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $fxml - An XML::Smart flag element on which we can invoke ->content.
#       $default - Default true/false value.  Default = Default NO.
#
# Returns:
#       Hash of default parameters configured in the application XML file.
################################################################################
#
sub xml_yes_no {
    my ($jconfig, $fxml, $default) = @_;

    if ($fxml) {
        return (defined $Jarvis::Config::yes_value{ lc ($fxml->content) }) ? 1 : 0;

    } else {
        return $default ? 1 : 0;
    }
}

################################################################################
# Returns a list of our default parameters.  Could be handy to some.
#
# Params:
#       $jconfig - Jarvis::Config object
#
# Returns:
#       Hash of default parameters configured in the application XML file.
################################################################################
#
sub default_parameters {
    my ($jconfig) = @_;

    $jconfig || die;

    my %default_parameters = ();
    
    my $pxml = $jconfig->{'xml'}{'jarvis'}{'app'}{'default_parameters'};
    if ($pxml && $pxml->{'parameter'}) {
        foreach my $parameter ($pxml->{'parameter'}('@')) {
            $default_parameters {$parameter->{'name'}->content} = $parameter->{'value'}->content;
        }
    }
    return %default_parameters;
}


################################################################################
# Construct a final list of "safe" parameters from the following sources.  
# The following order applies.  Later values will override earlier ones.
#
#   - Globally defined defaults.
#   - Safe-Named CGI parameters.
#   - Safe-Named REST parameters.
#   - Safe-Named per-Row parameters.
#   - Special __ variables.
#       __username  -> <logged-in-username>
#       __grouplist -> ('<group1>', '<group2>', ...)
#       __group:<groupname>  ->  1 (iff belong to <groupname>) or NULL
#
#   - Additional Safe parameters (e.g. from hooks, session store, etc.)
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               username
#               group_list
#
#       $user_args - Hash of CGI + numbered/named REST args (top level datasest).
#                    OR linked child args (for nested datasets).
#       $row_params - User-supplied (unsafe) hash of per-row parameters.
#
# Returns:
#       1
################################################################################
#
sub safe_variables {

    my ($jconfig, $user_args, $row_params) = @_;

    # Start with our default parameters.
    my %safe_params = &default_parameters ($jconfig);

    # Copy through the user-provided parameters.  Do not copy any user-provided
    # variable which begins with "__" (two underscores).  That prefix is strictly
    # reserved for our server-controlled "safe" parameters.
    if (defined $user_args) {
        foreach my $name (keys %$user_args) {
            if ($name =~ m/^_?[a-z0-9_\-]*$/i) {
                &Jarvis::Error::debug ($jconfig, "User REST Arg: '$name' => '%s'.", $user_args->{$name});
                $safe_params{$name} = $user_args->{$name};
            }
        }
    }
    if (defined $row_params) {
        foreach my $name (keys %$row_params) {
            if ($name =~ m/^_?[a-z][a-z0-9_\-]*$/i) {
                &Jarvis::Error::debug ($jconfig, "Row Parameter: '$name' => '%s'.", $row_params->{$name});
                $safe_params{$name} = $row_params->{$name};
            }
        }
    }

    # Our secure variables.  Note that __username and __group_list are null if
    # the user hasn't logged in
    #
    $safe_params{"__username"} = $jconfig->{'username'};
    $safe_params{"__group_list"} = $jconfig->{'group_list'};
    &Jarvis::Error::debug ($jconfig, "Secure Arg: __username => " . $safe_params{"__username"});
    &Jarvis::Error::debug ($jconfig, "Secure Arg: __group_list => " . $safe_params{"__group_list"});

    # And our separate groups.
    foreach my $group (split (',', $jconfig->{'group_list'})) {
        $safe_params{"__group:$group"} = 1;
        &Jarvis::Error::debug ($jconfig, "Secure Arg: __group:$group => 1");
    }

    # Finally, any additional safe parameters that might have been added by
    # login modules or other site-specific hooks.
    foreach my $name (keys %{ $jconfig->{'additional_safe'} }) {
        my $value = $jconfig->{'additional_safe'}{$name};
        $safe_params {$name} = $value;
        &Jarvis::Error::debug ($jconfig, "Secure Arg: $name => " . (defined $value ? "'$value'" : "NULL"));
    }

    return %safe_params;
}


################################################################################
#  We need to be able to set headers in hooks to do this we need to store the
#  headers before they are sent. The best place is inside the $jconfig
#
#   When ever printing headers the should be printed like this
#
#             &Jarvis::Config::add_http_headers($jconfig, {
#                -type => "text/plain; charset=UTF-8",
#                -cookie => $jconfig->{cookie},
#                'Cache-Control' => 'no-store, no-cache, must-revalidate'
#            });
#
#            print $cgi->header($jconfig->{http_headers});
#
#   - Additional Safe parameters (e.g. from hooks, session store, etc.)
#
# Params:
#       $jconfig - Jarvis::Config object
#
#
#       $header - Hash of the header key values paris
# Returns:
#       1
################################################################################
#

sub add_http_headers {
    my ($jconfig, $header) = @_;

    my @keys = keys %{ $header };

    for my $key (@keys) {
        $jconfig->{'http_headers'}->{$key} = $header->{$key};
        &Jarvis::Error::debug ($jconfig,"Adding header $key = " . ($header->{$key} || '') );
    }
}

1;
