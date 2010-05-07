###############################################################################
# Description:  Wrapper for our "Hooks".
#
#               A "Hook" is a Perl module which is registered with Jarvis, and
#               which then gets invoked at key points of the processing.  The
#               hook has the ability to
#
#               (a) Take additional actions triggered on the Jarvis behaviour
#                   e.g. custom logging, auditing, etc.
#
#               (b) Change the Jarvis behaviour, e.g. custom formatting, or
#                   security checking.
#
#               The hook points are as follows.  Your hook module MUST provide
#               all of these methods, even if they are empty functions.
#               Your hook functions must return "1" in all cases.  If you
#               wish to abort processing then call "die".
#
#                 start ($jconfig, $hook_params_href)
#                 CALLED: After all Jarvis setup is complete.
#
#                 before_all ($jconfig, $hook_params_href, $restful_params_href)
#                 CALLED: After transaction begins.  Just before any "before" SQL.
#
#                 before_one ($jconfig, $hook_params_href, $sql_params_href)
#                 CALLED: Before we execute the row SQL.
#
#                 after_one ($jconfig, $hook_params_href, $sql_params_href, $row_result_href)
#                 CALLED: After we execute the row SQL.  After any returning values are found.
#
#                 after_all ($jconfig, $hook_params_href, $restful_params_href)
#                 CALLED: Just before any "after" SQL.  This is before transaction ends.
#
#                 finish ($jconfig, $hook_params_href, $return_text_ref)
#                 CALLED: Just before return text is sent to client
#
#               Multiple hooks may be defined, they are simply invoked in
#               the order they appear in then application XML config file.
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

package Jarvis::Hook;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

################################################################################
# Load all our hook definitions.  Invoke the "start" method on each hook.
#
# Params:
#       $jconfig - Jarvis::Config object
#
# Returns:
#       1
################################################################################
#
sub start {
    my ($jconfig) = @_;

    my @hooks = ();

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    if ($axml->{'hook'}) {
        foreach my $hook (@{ $axml->{'hook'} }) {
            my $lib = $hook->{'lib'} ? $hook->{'lib'}->content : undef;
            my $module = $hook->{'module'}->content || die "Invalid configuration, <hook> configured with no module.";

            &Jarvis::Error::debug ($jconfig, "Found <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{'parameter'}) {
                foreach my $parameter ($hook->{'parameter'}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
                    $hook_parameter {$parameter->{'name'}->content} = $parameter->{'value'}->content;
                }
            }

            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter);
            push (@hooks, \%hook_def);
        }
    }
    $jconfig->{'hooks'} = \@hooks;

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        &Jarvis::Error::debug ($jconfig, "Using default libs: '" . (join ',', @{$jconfig->{'default_libs'}}) . "'". ($lib ? ", hook lib '$lib'." : ", no hook specific lib."));
        &Jarvis::Error::debug ($jconfig, "Loading hook module '$module'.");

        # Load the module.  This only needs to be done once.
        {
            map { eval "use lib \"$_\""; } @{$jconfig->{'default_libs'}};
            eval "use lib \"$lib\"" if $lib;
            eval "require $module";
            if ($@) {
                die "Cannot load hook module '$module': " . $@;
            }
        }

        # The module loaded OK, now try the "start" method.
        my $method = $module . "::start";
        &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
        {
            no strict 'refs';
            &$method ($jconfig, $hook_parameters_href);
        }
    }

    return 1;
}

################################################################################
# Invoke the "finish" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $return_text_ref - Reference to the text we are about to return.
#                          Hook(s) may modify this content before it is returned.
#
# Returns:
#       1
################################################################################
#
sub finish {
    my ($jconfig, $return_text_ref) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::finish";
        &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
        {
            no strict 'refs';
            &$method ($jconfig, $hook_parameters_href, $return_text_ref);
        }
    }

    return 1;
}

################################################################################
# Invoke the "before_all" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $restful_args_href - Reference to the rest args that will be given to
#                            any "before" SQL statement for this dataset.  Hook
#                            may modify these parameters.
#
# Returns:
#       1
################################################################################
#
sub before_all {
    my ($jconfig, $restful_args_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::before_all";
        &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
        {
            no strict 'refs';
            &$method ($jconfig, $hook_parameters_href, $restful_args_href);
        }
    }

    return 1;
}


################################################################################
# Invoke the "after_all" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $restful_args_href - Reference to the rest args that will be given to
#                            any "after" SQL statement for this dataset.  Hook
#                            may modify these parameters.
#
# Returns:
#       1
################################################################################
#
sub after_all {
    my ($jconfig, $restful_args_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::after_all";
        &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
        {
            no strict 'refs';
            &$method ($jconfig, $hook_parameters_href, $restful_args_href);
        }
    }

    return 1;
}

################################################################################
# Invoke the "before_one" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $sql_params_href - Reference to the processed and transformed args that
#                          are just about to be bound to the SQL parameters.  The
#                          hook may change these values.
#
# Returns:
#       1
################################################################################
#
sub before_one {
    my ($jconfig, $sql_params_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::before_one";
        &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
        {
            no strict 'refs';
            &$method ($jconfig, $hook_parameters_href, $sql_params_href);
        }
    }

    return 1;
}

################################################################################
# Invoke the "after_one" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $sql_params_href - Reference to the processed and transformed args that
#                          were bound to the SQL parameters.  No point changing.
#
#       $row_result_href - Reference to any row result generated by the
#                          insert/update, e.g. from a "returning" clause.
#                          The hook may change these values.
#
# Returns:
#       1
################################################################################
#
sub after_one {
    my ($jconfig, $sql_params_href, $row_result_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::after_one";
        &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
        {
            no strict 'refs';
            &$method ($jconfig, $hook_parameters_href, $sql_params_href, $row_result_href);
        }
    }

    return 1;
}


1;
