###############################################################################
# Description:  Performs a custom <plugin> dataset defined in the <app_name>.xml
#               file for this application.  Plugin modules are Perl modules
#               which we dynamically load.  We will load the specified module
#               and then call:
#
#                   <module>::do ($jconfig, %plugin_parameters)
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
# Look for a "plugin" dataset matching the given name.  If it exists then 
# execute the "::do" method on the configured plugin module.  This method
# should return the content to return to the user.  This content may include
# headers.  See the "add_headers" option on the plugin content.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               xml
#               cgi
#
#       $dataset - Name of the dataset we are requested to perform.
#
#       $user_args - Hash of CGI + numbered/named REST args
#
#       Note: For Jarvis 5.6 and later, $user_args is a HASH containing CGI
#       args plus numbered and named REST args.  
#
#       In earlier versions it was an ARRAY containing only the numbered REST 
#       args.  Your plugin will need modification if it uses the REST args.
#
# Returns:
#       0 if the dataset is not a known "plugin"
#       1 if the dataset is known and successful
#       die on error attempting to perform the dataset
################################################################################
#
sub do {
    my ($jconfig, $dataset, $user_args) = @_;

    ###############################################################################
    # See if we have any extra "plugin" datasets for this application.
    ###############################################################################
    #
    my $allowed_groups = undef;         # Access groups permitted, or "*" or "**"
    my $lib = undef;                    # Optional dir to add to lib path before module load
    my $module = undef;                 # Module name to load within lib path
    my $add_headers = undef;            # Should we add headers.
    my $default_filename = undef;       # A default return filename to use.
    my $filename_parameter = undef;     # Which CGI parameter contains our filename.
    my $mime_type = undef;              # Override the mime type if you want.

    # Start with the <default_parameters>, and add/replace any per-plugin configured parameters.
    my %plugin_parameters = &Jarvis::Config::default_parameters ($jconfig);         

    my $axml = $jconfig->{xml}{jarvis}{app};
    if ($axml->{plugin}) {
        foreach my $plugin (@{ $axml->{plugin} }) {
            my $plugin_ds = $plugin->{dataset}->content;
            &Jarvis::Error::dump ($jconfig, "Comparing '$dataset' to '$plugin_ds'.");
            next if (($dataset ne $plugin_ds) && ($dataset !~ m/^$plugin_ds\./));
            &Jarvis::Error::debug ($jconfig, "Found matching custom <plugin> dataset '$dataset'.");

            $allowed_groups = $plugin->{access}->content || die "No 'access' defined for plugin dataset '$dataset'\n";
            $lib = $plugin->{lib}->content if $plugin->{lib};
            $module = $plugin->{module}->content || die "No 'module' defined for plugin dataset '$dataset'\n";
            $add_headers = defined ($Jarvis::Config::yes_value {lc ($plugin->{add_headers}->content || "no")});
            $default_filename = $plugin->{default_filename}->content;
            $filename_parameter = $plugin->{filename_parameter}->content || 'filename';
            $mime_type = $plugin->{mime_type}->content;

            $jconfig->{dump} = $jconfig->{dump} || defined ($Jarvis::Config::yes_value {lc ($plugin->{dump}->content || "no")});
            $jconfig->{debug} = $jconfig->{dump} || $jconfig->{debug} || defined ($Jarvis::Config::yes_value {lc ($plugin->{debug}->content || "no")});

            # Get our parameters.  These are the configured parameters from the XML file,
            # which we handily load up for you, to avoid duplicating this code in every
            # module.  If you want CGI parameters from within your module, then you can access
            # the $jconfig->{cgi} CGI object.  Ditto for anything else you might want from
            # the $jconfig->{xml} XML::Smartt object.
            #
            if ($plugin->{parameter}) {
                foreach my $parameter ($plugin->{parameter}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Plugin Parameter: " . $parameter->{name}->content . " -> " . $parameter->{value}->content);
                    $plugin_parameters {$parameter->{name}->content} = $parameter->{value}->content;
                }
            }
            last;
        }
    }

    # If no match, that's fine.  Just say we couldn't do it.
    $module || return 0;

    # Perform CSRF checks.
    Jarvis::Main::check_csrf_protection ($jconfig, $allowed_groups);

    # Check security.
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{status} = "401 Unauthorized";
        die "Wanted plugin access: $failure\n"; # the \n supresses the die's normal at ... Plugin.pm line 135 output
    }

    # Figure out a filename.  It's not mandatory, if we don't have a default
    # filename and we don't have a filename_parameter supplied and defined then
    # we will return anonymous content in text/plain format.
    #
    my $filename = $user_args->{$filename_parameter} ? &File::Basename::basename ($user_args->{$filename_parameter}) : ($default_filename || undef);

    if (defined $filename) {
        &Jarvis::Error::debug ($jconfig, "Using filename '$filename'");

    } else {
        &Jarvis::Error::debug ($jconfig, "No return filename given.  MIME types and redirection will make best efforts.");
    }

    # Now load the module.
    #
    &Jarvis::Error::debug ($jconfig, "Using default libs: '" . (join ',', @{$jconfig->{default_libs}}) . "'". ($lib ? ", plugin lib '$lib'." : ", no plugin specific lib."));
    &Jarvis::Error::debug ($jconfig, "Loading plugin module '$module'.");

    {
        map { eval "use lib \"$_\""; } @{$jconfig->{default_libs}};
        eval "use lib \"$lib\"" if $lib;
        eval "require $module";
        if ($@) {
            die "Cannot load plugin module '$module': " . $@;
        }
    }

    # The module loaded OK, now try the "do" method.
    my $method = $module . "::do";
    &Jarvis::Error::debug ($jconfig, "Executing plugin method '$method'");
    my $output;
    {
        no strict 'refs';
        $output = &$method ($jconfig, $user_args, %plugin_parameters);
    }

    # Are we supposed to add headers?  Does that include a filename header?
    # Note that if we really wanted to, we could squeeze in
    if ($add_headers) {
        if (! $mime_type && $filename) {
            my $mime_types = MIME::Types->new;
            my $filename_type = $mime_types->mimeTypeOf ($filename);
            $mime_type = $filename_type ? $filename_type->type : 'text/plain';
        } elsif( ! $mime_type) {
            $mime_type = 'text/plain';
        }
        &Jarvis::Error::debug ($jconfig, "Plugin returning mime type '$mime_type'");

        if (defined $filename && ($filename ne '')) {
            print $jconfig->{cgi}->header(
                -type => $mime_type,
                'Content-Disposition' => $filename && "attachment; filename=$filename",
                -cookie => $jconfig->{cookie},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );

        } else {
            print $jconfig->{cgi}->header(
                -type => $mime_type,
                -cookie => $jconfig->{cookie},
                'Cache-Control' => 'no-store, no-cache, must-revalidate'
            );
        }
    }

    # Now print the output.  If the report didn't add headers like it was supposed
    # to, then this will all turn to custard.
    print $output;

    return 1;
}

1;
