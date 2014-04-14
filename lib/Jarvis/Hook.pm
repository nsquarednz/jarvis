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
#               Each hook is optional.  If you wish to abort processing then call "die".
#
#               Multiple hooks may be defined, they are simply invoked in
#               the order they appear in then application XML config file.
#
#               ************************************************************************
#               PLEASE SEE THE JARVIS GUIDE FOR DOCUMENTATION ON HOOK USE AND PARAMETERS
#               ************************************************************************
#
#               It is just too difficult to keep these docs in sync with the "Jarvis Guide",
#               so please just refer to the Jarvis Guide which is the official documentation.
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

###############################################################################
# LOCAL METHODS
###############################################################################

###############################################################################
# Load the module for a specified hook.  This is a local sub which
# is used to prepare per-QUERY global start hooks, and per-DATASET start hooks.
#
# Params:
#       $jconfig - Jarvis::Config object
#
#       $hook - Hook to load.
#
# Returns:
#       1
###############################################################################
#
sub load_module {
    my ($jconfig, $hook) = @_;

    my $lib = $hook->{lib};
    my $module = $hook->{module};
    my $hook_parameters_href = $hook->{parameters};

    &Jarvis::Error::debug ($jconfig, "Using default libs: '" . (join ',', @{$jconfig->{default_libs}}) . "'". ($lib ? ", hook lib '$lib'." : ", no hook specific lib."));
    &Jarvis::Error::debug ($jconfig, "Loading hook module '$module'.");

    # Load the module.  This only needs to be done once.
    {
        map { eval "use lib \"$_\""; } @{$jconfig->{default_libs}};
        eval "use lib \"$lib\"" if $lib;
        eval "require $module";
        if ($@) {
            die "Cannot load hook module '$module': " . $@;
        }
    }

    return 1;
}

###############################################################################
# Invoke the named method on just a single hook.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $hook - The hook to use.
#       $hook_name - The hook method name to execute.
#       @hook_args - The hook-specific args.
#
# Returns:
#       1
###############################################################################
#
sub invoke {
    my ($jconfig, $hook, $hook_name, @hook_args) = @_;

    my $module = $hook->{module};
    my $hook_parameters_href = $hook->{parameters};

    my $method = $module . "::" . $hook_name;
    {
        no strict 'refs';
        if (exists &$method) {
            &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            &$method ($jconfig, $hook_parameters_href, @hook_args);
        }            
    }

    return 1;
}

###############################################################################
# LOAD/UNLOAD and START/FINISH METHODS
###############################################################################

###############################################################################
# Load all our GLOBAL hook definitions and call the ::start hook on each one.
#
# Params:
#       $jconfig - Jarvis::Config object
#
# Returns:
#       1
###############################################################################
#
sub load_global {
    my ($jconfig) = @_;

    (defined $jconfig->{hooks}) || ($jconfig->{hooks} = []);

    # Set the hook nesting level to 0 (global hooks only).
    $jconfig->{hook_level} = 0;

    my $axml = $jconfig->{xml}{jarvis}{app};
    if ($axml->{hook}) {
        foreach my $hook (@{ $axml->{hook} }) {
            my $lib = $hook->{lib} ? $hook->{lib}->content : undef;
            my $module = $hook->{module}->content || die "Invalid global hook configuration, <hook> configured with no 'module' attribute.";

            &Jarvis::Error::debug ($jconfig, "Loading (level 0) global <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{parameter}) {
                foreach my $parameter ($hook->{parameter}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{name}->content . " -> " . $parameter->{value}->content);
                    $hook_parameter {$parameter->{name}->content} = $parameter->{value}->content;
                }
            }

            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter, level => 0);
            push (@{ $jconfig->{hooks} }, \%hook_def);
            &load_module ($jconfig, \%hook_def);

            my $method = $module . "::start";
            {
                no strict 'refs';
                exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
                exists &$method && &$method ($jconfig, \%hook_parameter);
            }
        }
    }

    return 1;
}

###############################################################################
# Unload our global hooks, invoke the "finish" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
# Returns:
#       1
###############################################################################
#
sub unload_global {
    my ($jconfig) = @_;

    # Unload all our global hooks.  These must be level zero.
    &Jarvis::Error::debug ($jconfig, "Unloading global (level 0) hooks.");

    # Invoke finish on all global hooks.
    foreach my $hook (@{ $jconfig->{hooks} }) {

        # All our dataset-level hooks should have been unloaded already.
        $hook->{level} && die "Dataset Hook remains at global hook unload time.  Impossible.";

        # Invoke the finish method with no extra parameters.
        &Jarvis::Error::debug ($jconfig, "Finishing global <hook> with module '%s'.", $hook->{module});
        &invoke ($jconfig, $hook, "finish");
    }

    # Finally remove ALL hooks (global and dataset). 
    $jconfig->{hooks} = [];
}

###############################################################################
# Load all dataset specific hook definitions and call ::start hook on each one.
#
# Params:
#       $jconfig - Jarvis::Config object
#
#       $dsxml - Dataset XML object.
#
# Returns:
#       1
###############################################################################
#
sub load_dataset {
    my ($jconfig, $dsxml) = @_;

    # Increment the hook level.  Level 0 are global.  Each nested dataset
    # will increment the level by one.
    my $hook_level = ++($jconfig->{hook_level});
    &Jarvis::Error::debug ($jconfig, "Loading dataset-specific hooks at hook level $hook_level.");

    if ($dsxml->{dataset}{hook}) {
        foreach my $hook (@{ $dsxml->{dataset}{hook} }) {
            my $lib = $hook->{lib} ? $hook->{lib}->content : undef;
            my $module = $hook->{module}->content || die "Invalid dataset hook configuration, <hook> configured with no module.";

            &Jarvis::Error::debug ($jconfig, "Loading (level $hook_level) dataset-specific <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{parameter}) {
                foreach my $parameter ($hook->{parameter}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{name}->content . " -> " . $parameter->{value}->content);
                    $hook_parameter {$parameter->{name}->content} = $parameter->{value}->content;
                }
            }

            # Note that you can NOT add $dsxml to the hook_def object.  You cannot
            # ever take a copy of an XML::Smart object, because the cleanup fails. 
            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter, level => $hook_level, dsxml => $dsxml);
            push (@{ $jconfig->{hooks} }, \%hook_def);
            &load_module ($jconfig, \%hook_def);

            my $method = $module . "::start";
            {
                no strict 'refs';
                exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
                exists &$method && &$method ($jconfig, \%hook_parameter, $dsxml);
            }            
        }
    }

    return 1;
}

###############################################################################
# Unload any dataset hooks added by the most recent call to load_dataset (), 
# invoke the "finish" method on each hook as we do so.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
# Returns:
#       1
###############################################################################
#
sub unload_dataset {
    my ($jconfig) = @_;

    # What is the current hook level?  Decrement it.
    my $hook_level = ($jconfig->{hook_level})--;
    &Jarvis::Error::debug ($jconfig, "Unloading dataset-specific (level $hook_level) hooks.");

    # Pop of hooks from the current level and invoke finish on them as we go.
    my $hooks_aref = $jconfig->{hooks};
    while (scalar @$hooks_aref && ($$hooks_aref[$#$hooks_aref]->{level} == $hook_level)) {
        my $hook = pop (@$hooks_aref);
        &Jarvis::Error::debug ($jconfig, "Finishing dataset-specific <hook> with module '%s'.", $hook->{module});
        &invoke ($jconfig, $hook, "finish", $hook->{dsxml});
    }
}

###############################################################################
# GLOBAL PER-QUERY HOOKS
###############################################################################

sub return_status {
    my ($jconfig, $extra_href, $return_text_ref) = @_;

    foreach my $hook (grep { ! $_->{level} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "return_status", $extra_href, $return_text_ref);
    }
    return 1;
}
sub return_fetch {
    my ($jconfig, $user_args_aref, $rows_aref, $extra_href, $return_text_ref) = @_;

    foreach my $hook (grep { ! $_->{level} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "return_fetch", $user_args_aref, $rows_aref, $extra_href, $return_text_ref);
    }
    return 1;
}
sub return_store {
    my ($jconfig, $dsxml, $user_args_aref, $results_aref, $extra_href, $return_text_ref) = @_;

    foreach my $hook (grep { ! $_->{level} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "return_store", $user_args_aref, $results_aref, $extra_href, $return_text_ref);
    }
    return 1;
}

###############################################################################
# GLOBAL UTILITY HOOKS
###############################################################################

sub after_login {
    my ($jconfig, $additional_safe_href) = @_;

    foreach my $hook (grep { ! $_->{level} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "after_login", $additional_safe_href);
    }
    return 1;
}
sub before_logout {
    my ($jconfig) = @_;

    foreach my $hook (grep { ! $_->{level} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "before_logout");
    }
    return 1;
}
sub pre_connect {
    my ($jconfig, $dbname, $dbtype, $dbconnect_ref, $dbusername_ref, $dbpassword_ref, $parameters_href) = @_;

    foreach my $hook (grep { ! $_->{level} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "pre_connect", $dbname, $dbtype, $dbconnect_ref, $dbusername_ref, $dbpassword_ref, $parameters_href);
    }
    return 1;
}

###############################################################################
# GLOBAL/DATASET PER-DATASET HOOKS
###############################################################################

sub dataset_pre_fetch {
    my ($jconfig, $dsxml, $safe_params_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "dataset_pre_fetch", $dsxml, $safe_params_href);
    }
    return 1;
}
sub dataset_pre_store {
    my ($jconfig, $dsxml, $safe_params_href, $rows_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "dataset_pre_store", $dsxml, $safe_params_href, $rows_aref);
    }
    return 1;
}
sub before_all {
    my ($jconfig, $dsxml, $safe_params_href, $fields_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "before_all", $dsxml, $safe_params_href, $fields_aref);
    }
    return 1;
}
sub after_all {
    my ($jconfig, $dsxml, $safe_params_href, $fields_aref, $results_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "after_all", $dsxml, $safe_params_href, $fields_aref, $results_aref);
    }
    return 1;
}
sub dataset_fetched {
    my ($jconfig, $dsxml, $safe_params_href, $rows_aref, $column_names_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "dataset_fetched", $dsxml, $safe_params_href, $rows_aref, $column_names_aref);
    }
    return 1;
}
sub dataset_stored {
    my ($jconfig, $dsxml, $safe_params_href, $results_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "dataset_stored", $dsxml, $safe_params_href, $results_aref);
    }
    return 1;
}

###############################################################################
# GLOBAL/DATASET PER-ROW HOOKS
###############################################################################

sub before_one {
    my ($jconfig, $dsxml, $safe_row_params_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "before_one", $dsxml, $safe_row_params_href);
    }
    return 1;
}
sub after_one {
    my ($jconfig, $dsxml, $safe_row_params_href, $row_result_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "after_one", $dsxml, $safe_row_params_href, $row_result_href);
    }
}

1;
