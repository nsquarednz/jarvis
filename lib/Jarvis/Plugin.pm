###############################################################################
# Description:  Performs a custom <plugin> action defined in the <app_name>.xml
#               file for this application.  Plugin modules are Perl modules
#               which we dynamically load.  We will load the specified module
#               and then call:
#
#                   <module>::Do ($jconfig, %plugin_parameters)
#
#               Where $jconfig is our Jarvis::Config option, and the
#               %plugin_parameters is a hash of name/value parameters loaded
#               from the master XML file.
#
#               We don't add any special parameters to the %plugin_parameters
#               (e.g. username, etc) since the module has access to the
#               Jarvis::Config and can grab what it needs any time.
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

use MIME::Types;

package Jarvis::Plugin;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

################################################################################
# Shows our current connection status.
#
# Params: 
#       $jconfig - Jarvis::Config object
#           READ
#               xml
#               cgi
#
#       $action - Name of the action we are requested to perform.
#
# Returns:
#       0 if the action is not a known "plugin"
#       1 if the action is known and successful
#       die on error attempting to perform the action
################################################################################
#
sub Do {
    my ($jconfig, $action) = @_;

    ###############################################################################
    # See if we have any extra "plugin" actions for this application.
    ###############################################################################
    #
    my $allowed_groups = undef;         # Access groups permitted, or "*" or "**"
    my $lib = undef;                    # Optional dir to add to lib path before module load
    my $module = undef;                 # Module name to load within lib path
    my $add_headers = undef;            # Should we add headers.
    my $default_filename = undef;       # A default return filename to use.
    my $filename_parameter = undef;     # Which CGI parameter contains our filename.

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    if ($axml->{'plugin'}) {
        foreach my $plugin (@{ $axml->{'plugin'} }) {
            next if ($action ne $plugin->{'action'}->content);
            &Jarvis::Error::Debug ($jconfig, "Found matching custom <plugin> action '$action'.");

            $allowed_groups = $plugin->{'access'}->content || &Jarvis::Error::MyDie ($jconfig, "No 'access' defined for plugin action '$action'");
            $lib = $plugin->{'lib'}->content;
            $module = $plugin->{'module'}->content || &Jarvis::Error::MyDie ($jconfig, "No 'module' defined for plugin action '$action'");
            $add_headers = defined ($Jarvis::Config::yes_value {lc ($plugin->{'add_headers'}->content || "no")});
            $default_filename = $plugin->{'default_filename'}->content;
            $filename_parameter = $plugin->{'filename_parameter'}->content;
        }
    }

    # If no match, that's fine.  Just say we couldn't do it.
    $module || return 0;

    # Check security.
    my $failure = &Jarvis::Login::CheckAccess ($jconfig, $allowed_groups);
    ($failure ne '') && &Jarvis::Error::MyDie ($jconfig, "Wanted plugin access: $failure");

    # Get our parameters.  These are the configured parameters from the XML file,
    # which we handily load up for you, to avoid duplicating this code in every
    # module.  If you want CGI parameters from within your module, then you can access
    # the $jconfig->{'cgi'} CGI object.  Ditto for anything else you might want from
    # the $jconfig->{'xml'} XML::Smartt object.
    #
    my %plugin_parameters = ();
    if ($axml->{'plugin'}{'parameter'}) {
        foreach my $parameter ($axml->{'plugin'}{'parameter'}('@')) {
            &Jarvis::Error::Debug ($jconfig, "Plugin Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
            $plugin_parameters {$parameter->{'name'}->content} = $parameter->{'value'}->content;
        }
    }

    # Figure out a filename.  It's not mandatory, if we don't have a default
    # filename and we don't have a filename_parameter supplied and defined then
    # we will return anonymous content in text/plain format.
    #
    my $filename = $jconfig->{'cgi'}->param ($filename_parameter) || $default_filename;

    # Now load the module.
    #
    &Jarvis::Error::Debug ($jconfig, "Using plugin lib '$lib'.");
    &Jarvis::Error::Debug ($jconfig, "Loading plugin module '$module'.");

    {
        eval "use lib \"$lib\" ; require $module";
        if ($@) {
            &Jarvis::Error::MyDie ($jconfig, "Cannot load login module '$module': " . $@);
        }
    }

    # The module loaded OK, now try the "Do" method.
    my $method = $module . "::Do";
    &Jarvis::Error::Log ($jconfig, "Executing plugin method '$method'");
    my $output;
    {
        no strict 'refs';
        $output = &$method ($jconfig, %plugin_parameters);
    }

    # Are we supposed to add headers?  Does that include a filename header?
    # Note that if we really wanted to, we could squeeze in 
    if ($add_headers) {
        my $mime_types = MIME::Types->new;
        my $mime_type = $mime_types->mimeTypeOf ($filename) || MIME::Types->type('text/plain');

        &Jarvis::Error::Debug ($jconfig, "Plugin returned mime type '" . $mime_type->type . "'");

        my $cookie = CGI::Cookie->new (-name => $jconfig->{'sname'}, -value => $jconfig->{'sid'});
        if ($filename) {
            print $jconfig->{'cgi'}->header(-type => $mime_type->type, 'Content-Disposition' => $filename && "inline; filename=$filename", -cookie => $cookie);

        } else {
            print $jconfig->{'cgi'}->header(-type => $mime_type->type, -cookie => $cookie);
        }
    }

    # Now print the output.  If the report didn't add headers like it was supposed
    # to, then this will all turn to custard.
    print $output;

    return 1;
}

1;