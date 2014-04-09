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
#               The hook points are as follows.  Each hook is optional.  
#               If you wish to abort processing then call "die".
#
#           GLOBAL QUERY HOOKS
#                 start ($jconfig, $hook_params_href)
#                 CALLED: After all Jarvis setup is complete.
#                   GLOBAL HOOKS
#
#                 return_status ($jconfig, $hook_params_href, $extra_href, $return_text_aref)
#                 CALLED: Before returning result of a "__status" request.
#                   GLOBAL HOOKS
#
#                 return_fetch ($jconfig, $hook_params_href, $safe_params_href, $return_object, $extra_href, $return_text_aref)
#                 CALLED: Before returning result of a "fetch" request.
#                   GLOBAL HOOKS
#
#                 return_store ($jconfig, $hook_params_href, $dsxml, $safe_params_href, $fields_aref, $results_aref, $extra_href, $return_text_aref)
#                 CALLED: Before returning result of a "store" request.
#                   GLOBAL HOOKS
#
#                 finish ($jconfig, $hook_params_href, $return_text_ref)
#                 CALLED: Before returned content is sent to client
#                   GLOBAL HOOKS
#
#           GLOBAL UTILITY HOOKS
#                 after_login ($jconfig, $hook_params_href, $additional_safe_href)
#                 CALLED: After first login for the session.
#                   GLOBAL HOOKS
#
#                 before_logout ($jconfig, $hook_params_href)
#                 CALLED: Before explicit session logout by the client
#                   GLOBAL HOOKS
#
#                 pre_connect ($jconfig, $dbname, $dbtype, $dbconnect_ref, $dbusername_ref, $dbpassword_ref, $parameters_href)
#                 CALLED: Before first connecting to each database.
#                   GLOBAL HOOKS
#
#           PER-DATASET
#                 start ($jconfig, $hook_params_href, $dsxml)
#                 CALLED: ("fetch" AND "store") Just after loading dataset config.
#                   DATASET HOOKS
#
#                 dataset_pre_fetch ($jconfig, $hook_params_href, $dsxml, $safe_params_href)
#                 CALLED: ("fetch" only) Before constructing the fetch request.
#                   GLOBAL and DATASET HOOKS
#
#                 dataset_fetched ($jconfig, $hook_params_href, $dsxml, $safe_params_href, $rows_aref, $column_names_aref, $extra_href)
#                 CALLED: ("fetch" only) After fetching results array for a single dataset.
#                   GLOBAL and DATASET HOOKS
#
#                 before_all ($jconfig, $hook_params_href, $dsxml, $safe_params_href, $fields_aref)
#                 CALLED: ("store" only) After transaction begins.  Before any "before" SQL.
#                   GLOBAL and DATASET HOOKS
#
#                 after_all ($jconfig, $hook_params_href, $dsxml, $safe_params_href, $fields_aref, $results_aref)
#                 CALLED: ("store" only) After any "after" SQL.  Before transaction ends.
#                   GLOBAL and DATASET HOOKS
#
#                 finish ($jconfig, $hook_params_href, $dsxml)
#                 CALLED: After dataset processing is complete.
#                   DATASET HOOKS
#
#           PER-ROW
#                 before_one ($jconfig, $hook_params_href, $dsxml, $safe_row_params_href)
#                 CALLED: ("store" only) Before we execute the row insert/update/delete SQL.
#                   GLOBAL and DATASET HOOKS
#
#                 after_one ($jconfig, $hook_params_href, $dsxml, $safe_row_params_href, $row_result_href)
#                 CALLED: ("store" only) After we execute the row insert/update/delete SQL.  After any returning values are found.
#                   GLOBAL and DATASET HOOKS
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

    my $axml = $jconfig->{xml}{jarvis}{app};
    if ($axml->{hook}) {
        foreach my $hook (@{ $axml->{hook} }) {
            my $lib = $hook->{lib} ? $hook->{lib}->content : undef;
            my $module = $hook->{module}->content || die "Invalid global hook configuration, <hook> configured with no module.";

            &Jarvis::Error::debug ($jconfig, "Found global <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{parameter}) {
                foreach my $parameter ($hook->{parameter}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{name}->content . " -> " . $parameter->{value}->content);
                    $hook_parameter {$parameter->{name}->content} = $parameter->{value}->content;
                }
            }

            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter, global => 1);
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

    # Invoke finish on all global hooks.
    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "finish");
    }

    # There should NOT be any dataset hooks remaining, they SHOULD be already unloaded.
    foreach my $hook (@{ $jconfig->{hooks} }) {
        if (! $hook->{global}) {
            &Jarvis::Error::log ($jconfig, "Dataset Hook '%s' still present at global hook unload time!", $hook->{module});
        }
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

    (defined $jconfig->{hooks}) || ($jconfig->{hooks} = []);

    if ($dsxml->{dataset}{hook}) {
        foreach my $hook (@{ $dsxml->{dataset}{hook} }) {
            my $lib = $hook->{lib} ? $hook->{lib}->content : undef;
            my $module = $hook->{module}->content || die "Invalid dataset hook configuration, <hook> configured with no module.";

            &Jarvis::Error::debug ($jconfig, "Found dataset-specific <hook> with module '$module'.");

            my %hook_parameter = ();
            if ($hook->{parameter}) {
                foreach my $parameter ($hook->{parameter}('@')) {
                    &Jarvis::Error::debug ($jconfig, "Hook Parameter: " . $parameter->{name}->content . " -> " . $parameter->{value}->content);
                    $hook_parameter {$parameter->{name}->content} = $parameter->{value}->content;
                }
            }

            # Note that you can NOT add $dsxml to the hook_def object.  You cannot
            # ever take a copy of an XML::Smart object, because the cleanup fails. 
            my %hook_def = ('module' => $module, 'lib' => $lib, 'parameters' => \%hook_parameter, global => 0, dsxml => $dsxml);
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
# Unload our dataset hooks, invoke the "finish" method on each hook.
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

    # Invoke finish on all dataset hooks.
    foreach my $hook (grep { ! $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "finish", $hook->{dsxml});
    }

    # Remove all dataset hooks.  Leave only the global hooks.
    my @global_hooks = grep { $_->{global} } @{ $jconfig->{hooks} };
    $jconfig->{hooks} = \@global_hooks;
}

###############################################################################
# PER-QUERY HOOKS
###############################################################################

###############################################################################
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
###############################################################################
#
sub return_status {
    my ($jconfig, $extra_href, $return_text_ref) = @_;

    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "return_status", $extra_href, $return_text_ref);
    }
    return 1;
}

###############################################################################
# Invoke the "return_fetch" method on each GLOBAL hook.  This occurs for all
# dataset within a regular SQL fetch.  If the fetch specifies more than one
# dataset in a comma-separated list, then we call this for each one.
#
# This hook may do one or more of:
#
#   - Add some extra per-dataset parameters (by modifying $extra_href)
#   - Completely modify the returned content (by modifying $rows_aref)
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session.  
#                           Changes will have no effect.
#
#       $return_object  - The complete nested object that we intend to
#                         encode in JSON/XML and send back to the client.
#                         This includes the "rows_aref" for each contained
#                         dataset in the fetch request.
#
#       NOTE: In Jarvis 4.0 this $return_object parameter replaced the
#       simple $rows_aref structure, as part of the extension to support
#       multiple datasets within a single fetch request.  It is likely
#       that your existing hook will be broken.  We apologise in advance.
#
#       $extra_href     - Hash of extra parameters to add to the root of
#                         the returned JSON/XML document.
#
#       $return_text_ref - Return text.  If we define this, it will be used
#                          instead of the default JSON/XML encoding.
#
# Returns:
#       1
###############################################################################
#
sub return_fetch {
    my ($jconfig, $safe_row_params_href, $return_object, $extra_href, $return_text_ref) = @_;

    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "return_fetch", $safe_row_params_href, $return_object, $extra_href, $return_text_ref);
    }
    return 1;
}


###############################################################################
# Invoke the "return_store" method on each GLOBAL hook.  This occurs for all 
# "store" requests on regular datasets.
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
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session.
#                           Changes will have no effect.
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
###############################################################################
#
sub return_store {
    my ($jconfig, $dsxml, $safe_params_href, $fields_aref, $results_aref, $extra_href, $return_text_ref) = @_;

    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "return_store", $safe_params_href, $fields_aref, $results_aref, $extra_href, $return_text_ref);
    }
    return 1;
}

###############################################################################
# UTILITY HOOKS
###############################################################################

###############################################################################
# Invoke the "after_login" method on each GLOBAL hook.
#
# Note that this hook is only invoked if the client was not previously logged
# in.  Don't bother overriding session expiry in this hook, as it won't last.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $additional_safe_href - Reference to the hash of additional safe
#                               parameters.  Hook module may add new ones.
#
# Returns:
#       1
###############################################################################
#
sub after_login {
    my ($jconfig, $additional_safe_href) = @_;

    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "after_login", $additional_safe_href);
    }
    return 1;
}

###############################################################################
# Invoke the "before_logout" method on each GLOBAL hook.
#
# Note that this hook is only invoked if the client was previously logged
# in.  Don't bother overriding anything in this hook in the session - it
# won't last.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
# Returns:
#       1
###############################################################################
#
sub before_logout {
    my ($jconfig) = @_;

    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "before_logout");
    }
    return 1;
}

###############################################################################
# Invoke the "pre_connect" method on each GLOBAL hook.
#
# This hook is invoked before attempting to connect to any database.  It allows
# the hook to possibly modify the connection parameters.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dbname         - The requested Jarvis dbname (e.g. "default").
#
#       $dbtype         - The requested Jarvis dbtype (e.g. "dbi").
#
#       $dbconnect_ref  - The DBI connection string.  Hook may modify.
#
#       $dbusername_ref - The DBI username string.  Hook may modify.
#
#       $dbpassword_ref - The DBI password string.  Hook may modify.
#
#       $parameters_href - The configured parameters.  Hook may modify.
#
# Returns:
#       1
###############################################################################
#
sub pre_connect {
    my ($jconfig, $dbname, $dbtype, $dbconnect_ref, $dbusername_ref, $dbpassword_ref, $parameters_href) = @_;

    foreach my $hook (grep { $_->{global} } @{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "pre_connect", $dbname, $dbtype, $dbconnect_ref, $dbusername_ref, $dbpassword_ref, $parameters_href);
    }
    return 1;
}

###############################################################################
# PER-DATASET HOOKS
###############################################################################

###############################################################################
# Invoke the "dataset_pre_fetch" method on a data hook.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session.
#                           Changes will be reflected in the query for THIS dataset only.
#
# Returns:
#       1
###############################################################################
#
sub dataset_pre_fetch {
    my ($jconfig, $dsxml, $safe_params_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "dataset_pre_fetch", $dsxml, $safe_params_href);
    }
    return 1;
}

###############################################################################
# Invoke the "before_all" method on each hook.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session.
#                           Changes will be reflected in the query.
#
#       $fields_aref    - The submitted rows we are about to apply.
#
# Returns:
#       1
###############################################################################
#
sub before_all {
    my ($jconfig, $dsxml, $safe_params_href, $fields_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "before_all", $dsxml, $safe_params_href, $fields_aref);
    }
    return 1;
}

###############################################################################
# Invoke the "after_all" method on each hook.  This occurs AFTER any <after>
# SQL has been executed.
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session.
#                           Changes will have no effect.
#
#       $fields_aref    - The submitted rows we just applied.
#
#       $results_aref   - Reference to the @results array we plan to return.
#
# Returns:
#       1
###############################################################################
#
sub after_all {
    my ($jconfig, $dsxml, $safe_params_href, $fields_aref, $results_aref) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "after_all", $dsxml, $safe_params_href, $fields_aref, $results_aref);
    }
    return 1;
}


###############################################################################
# Invoke the "dataset_fetched" method on each hook.  This occurs for all
# dataset within a regular SQL fetch.  If the fetch specifies more than one
# dataset in a comma-separated list, then we call this for each one.
#
# This hook may do one or more of:
#
#   - Add some extra per-dataset parameters (by modifying $extra_href)
#   - Modify the returned content (by modifying $rows_aref)
#
# Params:
#       $jconfig        - Jarvis::Config object
#
#       $dsxml          - The XML::Smart object for our dataset XML config.
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session.
#                           Changes will have no effect.
#
#       $rows_aref      - The array of return objects to be encoded.
#
#       $column_names_aref - Array of names of all returned columns.
#
#       $extra_href     - Hash of extra parameters to add inside the per-dataset
#                         object that we will return.
#
# Returns:
#       1
###############################################################################
#
sub dataset_fetched {
    my ($jconfig, $dsxml, $safe_row_params_href, $rows_aref, $column_names_aref, $extra_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "dataset_fetched", $dsxml, $safe_row_params_href, $rows_aref, $column_names_aref, $extra_href);
    }
    return 1;
}

###############################################################################
# PER-QUERY/PER-ROW HOOKS
###############################################################################

###############################################################################
# Invoke the "before_one" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $dsxml           - The XML::Smart object for our dataset XML config.
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session + Per-Row.
#                           Changes will affect only this row.
#
# Returns:
#       1
###############################################################################
#
sub before_one {
    my ($jconfig, $dsxml, $safe_row_params_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "before_one", $dsxml, $safe_row_params_href);
    }
    return 1;
}

###############################################################################
# Invoke the "after_one" method on each hook.
#
# Params:
#       $jconfig         - Jarvis::Config object
#
#       $dsxml           - The XML::Smart object for our dataset XML config.
#
#       $safe_params_href - The "all rows" safe params. 
#                           Default + CGI + REST + Session + Per-Row.
#                           Changes will have no effect.
#
#       $row_result_href - Reference to any row result generated by the
#                          insert/update, e.g. from a "returning" clause.
#                          The hook may change these values.
#
# Returns:
#       1
###############################################################################
#
sub after_one {
    my ($jconfig, $dsxml, $safe_row_params_href, $row_result_href) = @_;

    foreach my $hook (@{ $jconfig->{hooks} }) {
        &invoke ($jconfig, $hook, "after_one", $dsxml, $safe_row_params_href, $row_result_href);
    }
}

1;
