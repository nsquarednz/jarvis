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
#                 before_all ($jconfig, $hook_params_href, $restful_params_href, $fields_aref)
#                 CALLED: After transaction begins.  Just before any "before" SQL.
#
#                 before_one ($jconfig, $hook_params_href, $sql_params_href)
#                 CALLED: Before we execute the row SQL.
#
#                 after_one ($jconfig, $hook_params_href, $sql_params_href, $row_result_href)
#                 CALLED: After we execute the row SQL.  After any returning values are found.
#
#                 after_all ($jconfig, $hook_params_href, $restful_params_href, $fields_aref, $results_aref)
#                 CALLED: Just after any "after" SQL.  This is before transaction ends.
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
# Load all our GLOBAL hook definitions.
#
# Params:
#       $jconfig - Jarvis::Config object
#
# Returns:
#       1
################################################################################
#
sub load_global {
    my ($jconfig) = @_;

    (defined $jconfig->{'hooks'}) || ($jconfig->{'hooks'} = []);

    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    if ($axml->{'hook'}) {
        foreach my $hook (@{ $axml->{'hook'} }) {
            my $lib = $hook->{'lib'} ? $hook->{'lib'}->content : undef;
            my $module = $hook->{'module'}->content || die "Invalid global hook configuration, <hook> configured with no module.";

            &Jarvis::Error::debug ($jconfig, "Found global <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{'parameter'}) {
                foreach my $parameter ($hook->{'parameter'}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
                    $hook_parameter {$parameter->{'name'}->content} = $parameter->{'value'}->content;
                }
            }

            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter);
            push (@{ $jconfig->{'hooks'} }, \%hook_def);
        }
    }

    return 1;
}

################################################################################
# Load all dataset specific hook definitions.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dsxml - Dataset XML object.
#
# Returns:
#       1
################################################################################
#
sub load_dataset {
    my ($jconfig, $dsxml) = @_;

    (defined $jconfig->{'hooks'}) || ($jconfig->{'hooks'} = []);

    if ($dsxml->{'dataset'}{'hook'}) {
        foreach my $hook (@{ $dsxml->{'dataset'}{'hook'} }) {
            my $lib = $hook->{'lib'} ? $hook->{'lib'}->content : undef;
            my $module = $hook->{'module'}->content || die "Invalid dataset hook configuration, <hook> configured with no module.";

            &Jarvis::Error::debug ($jconfig, "Found dataset-specific <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{'parameter'}) {
                foreach my $parameter ($hook->{'parameter'}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{'name'}->content . " -> " . $parameter->{'value'}->content);
                    $hook_parameter {$parameter->{'name'}->content} = $parameter->{'value'}->content;
                }
            }

            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter);
            push (@{ $jconfig->{'hooks'} }, \%hook_def);
        }
    }

    return 1;
}

#################################################################
# Invoke the "start" method on each hook.
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

    # Now invoke "start" on all the hooks we found.
    foreach my $hook (@{ $jconfig->{'hooks'} }) {
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
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href);
        }
    }

    return 1;
}

################################################################################
# Invoke the "after_login" method on each hook.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $additional_safe_href - Reference to the has of additional safe
#                               parameters.  Hook module may add new ones.
#
# Returns:
#       1
################################################################################
#
sub after_login {
    my ($jconfig,  $additional_safe_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "after_login" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::after_login";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $additional_safe_href);
        }
    }

    return 1;
}

################################################################################
# Invoke the "before_all" method on each hook.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $rest_args_href - Reference to the RESTful args that will be given to
#                         any "before" SQL statement for this dataset.  Hook
#                         may modify these parameters.
#
#       $fields_aref    - The submitted rows we are about to apply.
#
# Returns:
#       1
################################################################################
#
sub before_all {
    my ($jconfig, $dsxml, $rest_args_href, $fields_aref) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "before_all" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::before_all";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $dsxml, $rest_args_href, $fields_aref);
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
#       $dsxml           - The XML::Smart object for our dataset XML config.
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
    my ($jconfig, $dsxml, $sql_params_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "before_one" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::before_one";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $dsxml, $sql_params_href);
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
#       $dsxml           - The XML::Smart object for our dataset XML config.
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
    my ($jconfig, $dsxml, $sql_params_href, $row_result_href) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "after_one" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::after_one";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $dsxml, $sql_params_href, $row_result_href);
        }
    }

    return 1;
}

################################################################################
# Invoke the "after_all" method on each hook.  This occurs AFTER any <after>
# SQL has been executed.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $rest_args_href - Our RESTful args.
#
#       $fields_aref    - The submitted rows we just applied.
#
#       $results_aref   - Reference to the @results array we plan to return.
#
# Returns:
#       1
################################################################################
#
sub after_all {
    my ($jconfig, $dsxml, $rest_args_href, $fields_aref, $results_aref) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "after_all" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::after_all";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $dsxml, $rest_args_href, $fields_aref, $results_aref);
        }
    }

    return 1;
}

################################################################################
# Invoke the "return_status" method on each hook.  This occurs for all "__status"
# requests.  It is performed just before we convert the status return results
# into JSON or XML.
#
# This hook may do one or more of:
#
#   - Add some extra root level parameters (by modifying $extra_href)
#   - Peform a custom encoding into text (by setting $return_text)
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $extra_href     - Hash of extra parameters to add to the root of
#                         the returned JSON/XML document.
#
#       $return_text_ref - Return text.  If we define this, it will be used
#                          instead of the default JSON/XML encoding.
#
# Returns:
#       1
################################################################################
#
sub return_status {

    my ($jconfig, $extra_href, $return_text_ref) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "return_status" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::return_status";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $extra_href, $return_text_ref);
        }
    }

    return 1;
}


################################################################################
# Invoke the "return_fetch" method on each hook.  This occurs for all "fetch"
# requests on regular datasets.  It is performed just before we convert the
# fetch return results into JSON or XML.
#
# This hook may do one or more of:
#
#   - Add some extra root level parameters (by modifying $extra_href)
#   - Completely modify the returned content (by modifying $rows_aref)
#   - Peform a custom encoding into text (by setting $return_text)
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $sql_params_href - All query args (CGI, restful, safe and default).
#
#       $rows_aref      - The array of return objects to be encoded.
#
#       $extra_href     - Hash of extra parameters to add to the root of
#                         the returned JSON/XML document.
#
#       $return_text_ref - Return text.  If we define this, it will be used
#                          instead of the default JSON/XML encoding.
#
# Returns:
#       1
################################################################################
#
sub return_fetch {

    my ($jconfig, $dsxml, $sql_params_href, $rows_aref, $extra_href, $return_text_ref) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "return_fetch" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::return_fetch";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $dsxml, $sql_params_href, $rows_aref, $extra_href, $return_text_ref);
        }
    }

    return 1;
}


################################################################################
# Invoke the "return_store" method on each hook.  This occurs for all "fetch"
# requests on regular datasets.  It is performed just before we convert the
# fetch return results into JSON or XML.
#
# This hook may do one or more of:
#
#   - Add some extra root level parameters (by modifying $extra_href)
#   - Completely modify the returned content (by modifying $results_aref)
#   - Peform a custom encoding into text (by setting $return_text)
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $rest_args_href - All RESTful args given to this store request.
#
#       $fields_aref    - The client-supplied per-row parameters, one per
#                         store request given to us.
#
#       $results_aref   - The results rows, one per store operation that
#                         we will return as the response.
#
#       $extra_href     - Hash of extra parameters to add to the root of
#                         the returned JSON/XML document.
#
#       $return_text_ref - Return text.  If we define this, it will be used
#                          instead of the default JSON/XML encoding of results.
#
# Returns:
#       1
################################################################################
#
sub return_store {
    my ($jconfig, $dsxml, $rest_args_href, $fields_aref, $results_aref, $extra_href, $return_text_ref) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "return_store" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::return_store";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href, $dsxml, $rest_args_href, $fields_aref, $results_aref, $extra_href, $return_text_ref);
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
# Returns:
#       1
################################################################################
#
sub finish {
    my ($jconfig) = @_;

    my @hooks = @{ $jconfig->{'hooks'} };

    # Now invoke "finish" on all the hooks we found.
    foreach my $hook (@hooks) {
        my $lib = $hook->{'lib'};
        my $module = $hook->{'module'};
        my $hook_parameters_href = $hook->{'parameters'};

        my $method = $module . "::finish";
        {
            no strict 'refs';
            exists &$method && &Jarvis::Error::debug ($jconfig, "Invoking hook method '$method'");
            exists &$method && &$method ($jconfig, $hook_parameters_href);
        }
    }

    return 1;
}

1;
