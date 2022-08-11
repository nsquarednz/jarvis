###############################################################################
# Description:  Dataset access functions for DBI drivers.
#
#               A DBI dataset is defined by a <dataset>.xml file which contains
#               the SQL to SELECT, UPDATE, INSERT, DELETE row(s).  A dataset
#               appears to be a single table to the web application.  In
#               practice, the SQL may interact with one or more tables.
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

package Jarvis::Agent::DBI;

use parent qw(Jarvis::Agent);

use sort 'stable';      # Don't mix up records when server-side sorting

use DBI qw(:sql_types);
use JSON;
use Data::Dumper;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;
use Jarvis::Hook;

################################################################################
# Get the SQL for the update, insert, and delete or whatever.
#
# Params:
#       $jconfig - Jarvis::Config object (NOT USED YET)
#       $which   - SQL Type ("select", "insert", "update", "delete")
#       $dsxml   - XML::LibXML object for dataset configuration
#
# Returns:
#       $raw_sql
#       die on error.
################################################################################
#
sub get_sql {
    my ($jconfig, $which, $dsxml) = @_;

    my $raw_sql = $dsxml->findvalue ("/dataset/$which") || return undef;
    $raw_sql =~ s/^\s*\-\-.*$//gm;   # Remove SQL comments
    $raw_sql = &trim ($raw_sql);
    return $raw_sql;
}

################################################################################
# Expand the SQL:
#       - Replace {{$args}} with ?
#       - Replace [[$args]] with text equivalent.
#       - Return list of ? arg names only.
#
# Note for historical reasons (i.e. Aviarc compatibility) we have allowed
# many different flavors of brackets.  E.g. the following are all supported:
#   {{var}}, {var}, {$var}, {{$var}}
#   [[var]], [$var]
#
# IN FUTURE WE WILL ATTEMPT TO CONSTRAIN TO A SINGLE FORMAT!
#   {$var} - for bind variables
#   [$var] - for textual substitution variables
#
# Note that for textual substitution, numeric values will not be quoted, while
# string values will be quoted using $dbh->quote.
#
# You can override this by specifying :noquote.  In that case, any characters
# outside the set [0-9a-zA-Z ,-_] will be deleted from the string, and quotes
# will not be used.
#
# You can alternatively specify :quote.  That will always quote.
#
# Params:
#       $jconfig - Jarvis config object.
#       $dbh - DB handle for quoting function.
#       $sql - SQL text.
#       $args_href - Hash of Fetch and REST args.
#
# Returns:
#       $sql_with_substitutions - SQL SCALAR
#       $variable_names - Array of variable names.
#       $variable_flags - Array of variable flags (undef or hash with name keys)
################################################################################
#
sub sql_with_substitutions {
    my ($jconfig, $dbh, $sql, $args_href) = @_;

    # Dump the available arguments at this stage.
    foreach my $k (sort (keys %$args_href)) {
        my $v = $args_href->{$k};
        if ((ref $v) eq '') {
            &Jarvis::Error::dump ($jconfig, "SQL available args: '$k' -> " . (defined $v ? "'" . $v . "'" : '<NULL>') . ".");

        } else {
            &Jarvis::Error::dump ($jconfig, "SQL available args: '$k' -> <" . (ref $v) . ">.");
        }
    }

    # Parse the update SQL to get a prepared statement, pulling out the list
    # of names of {{variables}} we replaced by ?.
    #
    # Parameters NAMES may contain only a-z, A-Z, 0-9, underscore(_), colon(:), dot(.) and hyphen(-)
    # Note pipe(|) is also allowed at this point as it separates (try-else variable names)
    my $sql2 = "";
    my @bits = split (/\{\{?\$?([\.a-zA-Z0-9_\-:\|\?]+(?:\![a-z]+)*)\}\}?/i, $sql);
    my @variable_names = ();
    my @variable_flags = ();

    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $name = $bits[$idx];
            my %flags = ();

            # Flags in bind variables are used for binding hints.  E.g. for DBD::Oracle
            # you can specify "!out" to request a variable to be bound as an in/out var
            # with bind_param_inout.
            #
            #   !out            Request an inout variable binding.
            #   !varchar        Call bind_param(_inout) with SQL_VARCHAR (the default)
            #   !numeric        Call bind_param(_inout) with SQL_NUMERIC
            #   !json           When referring to a reference, we might want to serialize it
            #                   as JSON for storage in some DBs like PostgreSQL.
            #
            # NOTE: The "?" test is not a flag in this context.  It is an indicator which 
            # belongs to the variable name and is handled in the names_to_values () method.
            # That is because it needs to inspect the values row to check for the existence 
            # of a row hash value (which we cannot do here, here we can only check for defined).
            #
            while ($name =~ m/^(.*)(\![a-z]+)$/) {
                $name = $1;
                my $flag = lc ($2);
                $flag =~ s/[^a-z\?]//g;
                $flags{$flag} = 1;
            }

            # The variable names may contain the "?" test indicator.
            push (@variable_names, $name);
            push (@variable_flags, \%flags);
            $sql2 .= "?";

        } else {
            $sql2 .= $bits[$idx];
        }
    }

    # Now perform any textual substitution of [[ ]] variables.  Note that
    # this really only makes sense with FETCH statements, and with rest
    # args in store statements.
    #
    # Parameters NAMES may contain only a-z, A-Z, 0-9, underscore(_), colon(:) and hyphen(-) plus:
    #
    #   pipe(|) is also allowed at this point as it separates (try-else variable names)
    #   question(?) is also allowed at this point, it is the "exists" test flag
    #
    @bits = split (/\[[\[\$]([a-zA-Z0-9_\-:\|]+(?:\![a-z]+)*)\]\]?/i, $sql2);

    my $sql3 = "";
    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $name = $bits[$idx];
            my %flags = ();

            ###################################################################
            # DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED
            # -- These features are officially documented, remember to
            # -- update the documentation if you change/extend then.
            ###################################################################
            #
            # Flags may be specified after the variable name with a colon separating the variable
            # name and the flag.  Multiple flags are permitted in theory, with a colon before
            # each flag.  Supported flags at this stage are:
            #
            #   !noquote        Don't wrap strings with quotes, instead just restrict content.
            #   !quote          Always quote, even for numbers.
            #   !raw            No quote, no restriction.  For experts only!
            #
            while ($name =~ m/^(.*)(\![a-z]+)$/) {
                $name = $1;
                my $flag = lc ($2);
                $flag =~ s/[^a-z]//g;
                $flags {$flag} = 1;
            }

            # The name may be a pipe-separated sequence of "names to try".
            my $value = undef;
            foreach my $option (split ('\|', $name)) {

                # NOTE: The "varname?" or "exists" test is not support here.
                if (($option =~ m/^\?/) || ($option =~ m/\?$/)) {
                    die "The existance test variable syntax is not supported in textual substitution.";
                }

                $value = $args_href->{$option};

                # NOTE: Non-SCALAR variables are silently ignored here!  Beware subtle bugs!
                next if (ref $value ne '');

                # NOTE: In textual substitution we take the first DEFINED value in the list.
                #
                # Compare this with the normal variable expansion mechanism where we take the
                # first row HASH variable which EXISTS (even if it is not defined).
                #
                last if (defined $value);
            }
            (defined $value) || ($value = '');

            # Numeric values by default are NOT quoted, unless requested.
            if ($value =~ m/^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && ! $flags{quote}) {
                # No change.

            # Raw flag performs NO changes ever!  Only allowed for SAFE variables (not client-supplied).
            } elsif ($flags{raw} && ($name =~ m/^__/)) {
                # No change.

            } elsif ($flags{noquote}) {
                $value =~ s/[^0-9a-zA-Z _\-,]//g;

            } else {
                $value = $dbh->quote($value);
            }
            &Jarvis::Error::debug ($jconfig, "Expanding: '$name' " . (scalar %flags ? ("[" . join (",", keys %flags) . "] ") : "") . "-> '$value'.");
            $sql3 .= $value;

        } else {
            $sql3 .= $bits[$idx];
        }
    }

    return ($sql3, \@variable_names, \@variable_flags);
}

# parses an attribute parameter string into a hash
sub parse_attr {
    my ($attribute_string) = @_;

    # split, trim and convert to hash (format: "pg_server_prepare => 0, something_else => 1")
    my %attributes = map { $_ =~ /^\s*(.*\S)\s*$/ ? $1 : $_ } map { split(/=>/, $_) } split(/,/, $attribute_string);

    return %attributes;
}

################################################################################
# Loads a specified SQL statement from the datasets, transforms the SQL into
# placeholder, pulls out the variable names, and prepares a statement.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dsxml - Dataset XML object
#       $dbh - Database handle
#       $ttype - Type of SQL to get.
#       $args_href - Hash of Fetch and REST args.
#
# Returns:
#       STM hash with keys
#               {ttype}
#               {raw_sql}
#               {sql_with_substitutions}
#               {returning}
#               {sth}
#               {vnames_aref}
#               {vflags_aref}
#               {nolog_dataset}
#               {nolog_dbh}
#               {noerr_dataset}
#               {noerr_dbh}
#               {error}      (Set later, to error message from latest action)
#               {retval}     (Set later, return value of latest action)
#
#       Or undef if no SQL.
################################################################################
sub parse_statement {
    my ($jconfig, $dataset_name, $dsxml, $dbh, $ttype, $args_href) = @_;

    my $stm = {};

    # Get and check the raw SQL, before parameter -> ? substitution.
    &Jarvis::Error::debug ($jconfig, "Parsing statement for transaction type '$ttype'");
    $stm->{ttype} = $ttype;
    $stm->{raw_sql} = &get_sql ($jconfig, $ttype, $dsxml);
    if (! $stm->{raw_sql}) {
        &Jarvis::Error::debug ($jconfig, "No SQL found for type '$ttype'");
        return undef;
    }
    &Jarvis::Error::dump ($jconfig, "SQL as read from XML = " . $stm->{raw_sql});

    # Does this insert return rows?
    $stm->{returning} = &Jarvis::Config::xml_yes_no ($jconfig, $dsxml->findvalue ("/dataset/$ttype/\@returning"));
    &Jarvis::Error::debug ($jconfig, "Returning? = " . $stm->{returning});

    # Get our SQL with placeholders and prepare it.
    my ($sql_with_substitutions, $variable_names, $variable_flags) = &sql_with_substitutions ($jconfig, $dbh, $stm->{raw_sql}, $args_href);
    $stm->{sql_with_substitutions} = $sql_with_substitutions;
    $stm->{vnames_aref} = $variable_names;
    $stm->{vflags_aref} = $variable_flags;

    &Jarvis::Error::dump ($jconfig, "SQL after substition = " . $sql_with_substitutions);

    # get db-specific parameters
    my $dbxml = &Jarvis::DB::db_config ($jconfig, $dsxml->findvalue ('/dataset/@dbname'), $dsxml->findvalue ('/dataset/@dbtype'));

    # Use special prepare parameters
    my $db_prepare_str = $dbxml->findvalue ('./@prepare');
    my $ds_prepare_str = $dsxml->findvalue ("/dataset/$ttype/\@prepare");

    my %prepare_attr = ();
    foreach my $prepare_str (grep { $_ } ($db_prepare_str, $ds_prepare_str)) {
        &Jarvis::Error::debug ($jconfig, "Prepare += '$prepare_str'");
        %prepare_attr = (%prepare_attr, parse_attr($prepare_str));
        &Jarvis::Error::dump ($jconfig, "Prepare after parsing =\n" . Dumper(%prepare_attr));
    }

    # Do the prepare, with RaiseError & PrintError disabled.
    {
        local $dbh->{RaiseError};
        local $dbh->{PrintError};
        $stm->{sth} = $dbh->prepare ($sql_with_substitutions, \%prepare_attr) ||
            die "Couldn't prepare statement for $ttype on '$dataset_name'.\nSQL ERROR = '" . $dbh->errstr . "'.\n";
    }

    # NOTE: "nolog" : Report back to client.  Do not log.
    #       "noerr" : Do NOT report back to client.  Do not log.

    # Log and error suppression patterns (dataset)
    $stm->{nolog_dataset} = ($dsxml->exists ("/dataset/$ttype/\@nolog") ? $dsxml->findvalue ("/dataset/$ttype/\@nolog") : '');
    $stm->{noerr_dataset} = ($dsxml->exists ("/dataset/$ttype/\@noerr") ? $dsxml->findvalue ("/dataset/$ttype/\@noerr") : '');

    # Log and error suppression patterns (database global)
    $stm->{nolog_dbh} = ($dbxml->{nolog} ? $dbxml->{nolog} : '');
    $stm->{noerr_dbh} = ($dbxml->{noerr} ? $dbxml->{noerr} : '');

    # Warning/error suppression pattern
    $stm->{ignore} = ($dsxml->exists ("/dataset/$ttype/\@ignore") ? $dsxml->findvalue ("/dataset/$ttype/\@ignore") : '');

    return $stm;
}

################################################################################
# Check if error message should be supressed by a "nolog" or "noerr" pattern.
#
# A nolog and/or noerr pattern can be specified either:
#   a) In a dataset, e.g.
#         <update nolog="uq_EducatorPoliceChecks_PoliceCheckDate">
#
#   b) Globally in the <database><nolog>...</nolog></database> field.
#
# Params:
#       $stm - statement object as returned by parse_statement
#       $message - error message to match against nolog flag
#
# Returns:
#       1 if message matches nolog flag
#       0 otherwise
################################################################################
sub nolog {
    my ($stm, $message) = @_;

    # "noerr" always implies "nolog".
    if (&noerr ($stm, $message)) {
        return 1;
    }
    my $nolog = $stm->{nolog_dataset};
    if ($nolog && $message =~ /$nolog/) {
        return 1;
    }
    $nolog = $stm->{nolog_dbh};
    if ($nolog && $message =~ /$nolog/) {
        return 1;
    }
    return 0;
}
sub noerr {
    my ($stm, $message) = @_;

    my $noerr = $stm->{noerr_dataset};
    if ($noerr && $message =~ /$noerr/) {
        return 1;
    }
    $noerr = $stm->{noerr_dbh};
    if ($noerr && $message =~ /$noerr/) {
        return 1;
    }
    return 0;
}

################################################################################
# check if error message should be supressed due to ignore flag
#
# Params:
#       $stm - statement object as returned by parse_statement
#       $message - error message to match against ignore flag
#
# Returns:
#       1 if message matches ignore flag
#       0 otherwise
################################################################################
sub ignore {
    my ($stm, $message) = @_;

    my $ignore = $stm->{ignore};
    if ($ignore && $message =~ /$ignore/) {
        return 1;
    } else {
        return 0;
    }
}

################################################################################
# Executes a statement.  On failure:
#       - Determine error string.
#       - Print to STDERR
#       - Finish the Statement Handle
#       - Update 'error' and 'retval' in $stm object.
#       - Return error string.
#
# You might ask why we have a separate 'error' string and don't use the one
# on the "sth" statement handle?  Well, that's because in some rare cases
# we can actually get a Perl failure in the "eval" without an underlying DBD
# exception.
#
# The "retval" parameter is the number of rows modified in an update/insert/delete.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $stm - A STM object created by &parse_statement.
#
# Returns:
#       1 (success) or 0 (failure)
################################################################################
sub statement_execute {
    my ($jconfig, $stm, $args) = @_;

    my $err_handler = $SIG{__DIE__};
    $stm->{retval} = 0;
    $stm->{error} = undef;

    eval {
        no warnings 'uninitialized';
        $SIG{__DIE__} = sub {};

        # Statement handle.
        my $sth = $stm->{sth};

        #######################################################################
        # DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED
        # -- These features are officially documented, remember to
        # -- update the documentation if you change/extend then.
        #######################################################################
        #
        # Do we have any "!out" flagged variables?
        my $out_flag = 0;

        # Do we have any special handling that we need to perform on any of our SQL parameters?
        my $preproc_flag = 0;

        foreach my $flag (@{ $stm->{vflags_aref} }) {

            # Not all variables have flags.
            next if (! defined $flag);

            # Examine which flags we have.
            $out_flag     = 1 if $flag->{out};
            $preproc_flag = 1 if $flag->{json};
        }

        # Do any of our flags involve pre-processing/transforming input variables?
        if ($preproc_flag) {
            &Jarvis::Error::debug ($jconfig, "At least one bind variable requires pre-processing.");
            foreach my $i (0 .. $#$args) { 
                # Get the flags for the current argument.
                my $flags = $stm->{vflags_aref}[$i];

                # Handle JSON encoded values. We need to take the requested argument which is
                # expected to be a HASH reference and encode it as JSON we can use.
                if (defined $flags->{json}) {
                    my $json_str = $$args[$i];

                    if (defined $json_str) {
                        eval {
                            $$args[$i] = JSON::encode_json ($json_str);
                        };
                        if ($@) {
                            die "Failed to encode JSON bind value: $@\n";
                        }
                    }
                }
            }
        }

        # The cases with "!out" variables is suddenly more interesting.
        if ($out_flag) {
            my %out_arg_refs = ();

            # Note: The following arrays are all the same size (one per bind var).
            #   @$args           # Arg values.
            #   @{ $stm->{vnames_aref} }  # Arg names.
            #   @{ $stm->{vflags_aref} }  # Arg flags.
            #
            &Jarvis::Error::debug ($jconfig, "At least one bind variable is flagged '!out'.  Use bind_param () mechanism.");
            foreach my $i (0 .. $#$args) {
                my $flags = $stm->{vflags_aref}[$i];
                my $sql_type = SQL_VARCHAR;
                if (defined $flags->{numeric}) {
                    $sql_type = SQL_NUMERIC;
                }

                if ($flags->{out}) {
                    my $name = $stm->{vnames_aref}[$i];
                    my $var = $$args[$i];
                    $out_arg_refs{$name} = \$var;
                    &Jarvis::Error::debug ($jconfig, "Binding variable [$i] as SQL type [$sql_type] (IN/OUT) (Name = '$name').");
                    $sth->bind_param_inout ($i + 1, \$var, $sql_type);

                } else {
                    &Jarvis::Error::debug ($jconfig, "Binding variable [$i] as SQL type [$sql_type] (IN).");
                    $sth->bind_param ($i + 1, $$args[$i], $sql_type);
                }
            }

            # Execute using the previously attached args.
            $stm->{retval} = $sth->execute ();

            # We have some returned arg refs.
            $stm->{returned} = \%out_arg_refs;

            # Hey, this statement is "returning" be definition!
            if (! $stm->{returning}) {
                &Jarvis::Error::debug ($jconfig, "Forcing the 'returning' attribute on this statement.");
                $stm->{returning} = 1;
            }

        # The case with no "!out" flagged variables is very much simpler.
        } else {
            $stm->{retval} = $sth->execute (@$args);
        }
    };
    $SIG{__DIE__} = $err_handler;

    my $error_message = $stm->{sth}->errstr || $@ || $DBI::errstr;
    if (($error_message && !ignore($stm, $error_message)) || (!defined $stm->{retval})) {
        # ensure we have an error message to return
        $error_message = $error_message || 'Unknown error SQL execution error.';
        $error_message =~ s/\s+$//;

        if (&nolog ($stm, $error_message)) {
            &Jarvis::Error::debug ($jconfig, "Failure executing SQL. Log disabled.");

        } else {
            &Jarvis::Error::log ($jconfig, "Failure executing SQL for '" . $stm->{ttype} . "'.  Details follow.");
            &Jarvis::Error::log ($jconfig, $stm->{sql_with_substitutions}) if $stm->{sql_with_substitutions};
            &Jarvis::Error::log ($jconfig, $error_message);
            &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @$args) || 'NONE'));
        }

        $stm->{sth}->finish;

        if (! &noerr ($stm, $error_message)) {
            $stm->{error} = $error_message;
        }
        return 0;
    }

    &Jarvis::Error::debug ($jconfig, 'Successful statement execution.  RetVal = ' . $stm->{retval});
    return 1;
}

################################################################################
# Loads the data for the current dataset(s), and puts it into our return data
# array so that it can be presented to the client in JSON or XML or whatever.
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return
# object.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $column_names_aref - Array of tuple column names, if available.
#       $dbh - Database handle of the correct type to match the dataset.
#       $sth - Statement handle which has just performed a "fetch" statement.
#
# Returns:
#       $column_types_href - Hash mapping column name -> $TYPE_*. 
################################################################################
sub get_column_types {
    my ($jconfig, $column_names_aref, $dbh, $sth) = @_;

    # This may not necessaryily work.
    if (! $column_names_aref) {
        &Jarvis::Error::debug ($jconfig, 'No column names.  Cannot apply JSON proper types.');
        return undef;
    }

    # We're going to try and determine useful types (for JSON conversion).
    my $column_types_href = {};

    # Silly old SQLite returns types as names, not as proper type codes.
    #
    if ($dbh->{Driver}{Name} eq 'SQLite') {

        # Note that:
        #
        #  a) the SQLite types returned are STRING names, not the standard SQL_BOOLEAN constants.
        #  b) the SQLite types returned seem to be mixed case (maybe they retain the case specified at creation time).
        #
        my $column_types_aref = $sth->{TYPE};
        if ($column_types_aref) {
            &Jarvis::Error::debug ($jconfig, 'Checking for returned type conversion (SQLite).');

            foreach my $i (0 .. $#$column_names_aref) {
                my $name = $$column_names_aref[$i];
                my $type = $$column_types_aref[$i];

                &Jarvis::Error::dump ($jconfig, 'Column name [%s] has type [%s].', $name, $type);
                if (lc ($type) eq 'integer') {
                    &Jarvis::Error::debug ($jconfig, 'Detecting column [%s] as NUMERIC.');
                    $column_types_href->{$name} = $Jarvis::Dataset::TYPE_NUMERIC;
                }
            }
        }

    # All other DB types, do our best with the SQL constants.
    } elsif ($dbh->{Driver}{Name} eq 'Pg') {

        # Use the PostgreSQL type list.  It has extra fields like JSON in it.
        my $column_types_aref = $sth->{pg_type};
        if ($column_types_aref) {
            &Jarvis::Error::debug ($jconfig, 'Checking for returned type conversion (Pg).');

            foreach my $i (0 .. $#$column_names_aref) {
                my $name = $$column_names_aref[$i];
                my $type = $$column_types_aref[$i];

                &Jarvis::Error::dump ($jconfig, 'Column name [%s] has type [%s].', $name, $type);

                if ($type eq 'int4') {
                    &Jarvis::Error::debug ($jconfig, 'Detecting column [%s] as NUMERIC.');
                    $column_types_href->{$name} = $Jarvis::Dataset::TYPE_NUMERIC;

                } elsif ($type eq 'bool') {
                    &Jarvis::Error::debug ($jconfig, 'Detecting column [%s] as BOOLEAN.');
                    $column_types_href->{$name} = $Jarvis::Dataset::TYPE_BOOLEAN;

                # Oh yeah, Baby.  This is what we live for.
                } elsif ($type eq 'json') {
                    &Jarvis::Error::debug ($jconfig, 'Detecting column [%s] as JSON.');
                    $column_types_href->{$name} = $Jarvis::Dataset::TYPE_JSON;
                }
            }
        }

    # All other DB types, do our best with the SQL constants.
    } else {

        # This is the only TYPE list we can trust.
        my $column_types_aref = $sth->{TYPE};
        if ($column_types_aref) {
            &Jarvis::Error::debug ($jconfig, 'Checking for returned type conversion (Other - %s).', $dbh->{Driver}{Name});

            foreach my $i (0 .. $#$column_names_aref) {
                my $name = $$column_names_aref[$i];
                my $type = $$column_types_aref[$i];

                &Jarvis::Error::dump ($jconfig, 'Column name [%s] has type [%s].', $name, $type);
                if ($type eq SQL_NUMERIC) {
                    &Jarvis::Error::debug ($jconfig, 'Detecting column [%s] as NUMERIC.');
                    $column_types_href->{$name} = $Jarvis::Dataset::TYPE_NUMERIC;

                } elsif ($type eq SQL_BOOLEAN) {
                    &Jarvis::Error::debug ($jconfig, 'Detecting column [%s] as BOOLEAN.');
                    $column_types_href->{$name} = $Jarvis::Dataset::TYPE_BOOLEAN;
                }
            }
        }
    }

    return $column_types_href;
}

################################################################################
# AGENT METHOD OVERRIDE
################################################################################

################################################################################
# Begin, Rollback, Commit handlers.  If your DBH supports transactions then
# please call them now.
#
# Params:
#       $class - Agent classname.
#       $jconfig - Jarvis::Config object
#       $dbh - Database handle of the correct type to match the dataset.
#
# Returns:
#       undef
################################################################################
sub transaction_begin {
    my ($class, $jconfig, $dbh) = @_;

    $dbh->begin_work ();

    return undef;
}
sub transaction_rollback {
    my ($class, $jconfig, $dbh) = @_;

    # Use "eval" as some drivers (e.g. SQL Server) will have already rolled-back on the
    # original failure, and hence a second rollback will fail.
    eval { local $SIG{__DIE__}; $dbh->rollback (); };

    return undef;
}
sub transaction_commit {
    my ($class, $jconfig, $dbh) = @_;

    $dbh->commit ();

    return undef;
}

################################################################################
# Loads the data for the current dataset(s), and puts it into our return data
# array so that it can be presented to the client in JSON or XML or whatever.
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return
# object.
#
# Params:
#       $class - Agent classname.
#       $jconfig - Jarvis::Config object
#           READ
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#
#       $dataset_name - Name of single dataset we are fetching from.
#       $dsxml - Dataset's XML configuration object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $safe_params - All our safe parameters.
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
#       $column_types_href - Hash mapping column name -> $TYPE_*. 
################################################################################
sub fetch_inner {
    my ($class, $jconfig, $dataset_name, $dsxml, $dbh, $safe_params) = @_;

    # Get our STM.  This has everything attached.
    my $stm = &parse_statement ($jconfig, $dataset_name, $dsxml, $dbh, 'select', $safe_params) ||
        die "Dataset '$dataset_name' has no SQL of type 'select'.\n";

    # Convert the parameter names to corresponding values.
    my @args = &Jarvis::Dataset::names_to_values ($jconfig, $stm->{vnames_aref}, $safe_params);

    # Execute Select, return on error
    &statement_execute ($jconfig, $stm, \@args);
    $stm->{error} && die $stm->{error} . "\n";

    # Fetch the data.
    my $rows_aref = $stm->{sth}->fetchall_arrayref({});

    # See if we can get column names.  If we can't get them legitimately
    # then try sniffing them from the results, though we will lose any column
    # ordering that might have otherwise existed in the original query.
    my $column_names_aref = $stm->{sth}{NAME};
    if ((scalar @$rows_aref) && ! $column_names_aref) {
        &Jarvis::Error::debug ($jconfig, 'No column names from query.  Try sniffing results.');
        my @column_names = sort (keys (%{ $$rows_aref[0] }));
        $column_names_aref = \@column_names;
    }

    # See if we can get type information?
    my $column_types_href = &get_column_types ($jconfig, $column_names_aref, $dbh, $stm->{sth});

    # Finish the statement handle.
    $stm->{sth}->finish;

    return ($rows_aref, $column_names_aref, $column_types_href);
}

################################################################################
# Execute the "before" statement for a dataset.  This a once-only statement
# that occurs prior to any row updates.
#
# Params:
#       $class - Agent classname.
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in MDX
#               username            Used for {{username}} in MDX
#               group_list          Used for {{group_list}} in MDX
#               format              Either "json" or "xml" or "csv".
#
#       $dataset_name - Name of single dataset we are fetching from.
#       $dsxml - Dataset's XML configuration object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $before_params_href - All our before parameters parameters.
#
# Returns:
#       undef on success, "Error Text" on failure.
################################################################################
sub execute_before {
    my ($class, $jconfig, $dataset_name, $dsxml, $dbh, $before_params_href) = @_;

    my $bstm = &parse_statement ($jconfig, $dataset_name, $dsxml, $dbh, 'before', $before_params_href);
    if ($bstm) {
        my @barg_values = &Jarvis::Dataset::names_to_values ($jconfig, $bstm->{vnames_aref}, $before_params_href);

        &statement_execute($jconfig, $bstm, \@barg_values);
        if ($bstm->{error}) {
            my $message = $bstm->{error};
            $message =~ s/^Server message number=[0-9]+ severity=[0-9]+ state=[0-9]+ line=[0-9]+ server=[A-Z0-9\\]+text=//i;
            return $message;
        }
    }

    return undef;
}

################################################################################
# Performs an update to the specified table underlying the named dataset.
#
# Params:
#       $class - Agent classname.
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Submitted content and content-type.
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               format              Either "json" or "xml" (not "csv").
#
#       $dataset_name - Name of single dataset we are storing to.
#       $dsxml - Dataset XML object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $stms - Hash of pre-prepared statements by row type.
#       $row_ttype - Transaction type for this row.
#       $safe_params - All our safe parameters.
#       $fields_href - The raw fields.  We echo those for some DB types.
#
# Returns:
#       $row_result - HASH REF containing {
#           success => 0/1
#           modified => num-modified,
#           message => Error message if not success,
#           returning => ARRAY of returned rows
#       }
#       die on hard error.
################################################################################
#
sub store_inner {
    my ($class, $jconfig, $dataset_name, $dsxml, $dbh, $stms, $row_ttype, $safe_params, $fields_href) = @_;

    # Get the statement type for this ttype if we don't have it.  This raises debug.
    if (! $stms->{$row_ttype}) {
        $stms->{$row_ttype} = &parse_statement ($jconfig, $dataset_name, $dsxml, $dbh, $row_ttype, $safe_params);
    }

    # Check we have an stm for this row.
    my $stm = $stms->{$row_ttype} ||
        die "Dataset '$dataset_name' has no SQL of type '$row_ttype'.\n";

    # Determine our argument values.
    my @arg_values = &Jarvis::Dataset::names_to_values ($jconfig, $stm->{vnames_aref}, $safe_params);

    # Execute
    my $row_result = {};
    my $returning_types = undef;

    &statement_execute ($jconfig, $stm, \@arg_values);
    $row_result->{modified} = $stm->{retval} || 0;

    # On failure, we will still return valid JSON/XML to the caller, but we will indicate
    # which request failed and will send back an overall "non-success" flag.
    #
    if ($stm->{error}) {
        $row_result->{success} = 0;
        $row_result->{modified} = 0;
        $row_result->{message} = $stm->{error};

    # Suceeded.  Set per-row status, and fetch the returned results, if this
    # operation indicates that it returns values.
    #
    } else {
        $row_result->{success} = 1;

        # Try and determine the returned values (normally the auto-increment ID)
        if ($stm->{returning}) {

            # If you flagged any variables as "!out" then we will have used
            # bind_param_inout () and copied the output vars into $stm->{returned}.
            # In this case, all the work is already done, and we just need to copy
            # everything through.
            if ($stm->{returned}) {

                my $row = {};
                foreach my $name (keys %{ $stm->{returned} }) {
                    my $value_ref = $stm->{returned}{$name};
                    $row->{$name} = $$value_ref;
                }

                $row_result->{returning} = [ $row ];
                &Jarvis::Error::debug ($jconfig, "Copied single row from bind_param_inout results.");

            # SQLite uses the last_insert_rowid() function for returning IDs.
            # This is very special case handling.  We echo the input fields too!
            #
            } elsif ($dbh->{Driver}{Name} eq 'SQLite') {

                my $rowid = $dbh->func('last_insert_rowid');
                if ($rowid) {
                    my $returning_row = {};
                    foreach my $field (keys %$fields_href) {
                        (ref $fields_href->{$field} eq '') && ($returning_row->{$field} = $fields_href->{$field});
                    }
                    $returning_row->{id} = $rowid;
                    $row_result->{returning} = [ $returning_row ];
                    &Jarvis::Error::debug ($jconfig, "Used SQLite last_insert_rowid to get returned 'id' => '$rowid'.");

                } else {
                    &Jarvis::Error::log ($jconfig, "Used SQLite last_insert_rowid but it returned no id.");
                }

            # Otherwise: See if the query had a built-in fetch.  Under PostgreSQL (and very
            # likely also under other drivers) this will fail if there is no current
            # query.  I.e. if you have no "RETURNING" clause on your insert.
            #
            } else {
                my $returning_aref = $stm->{sth}->fetchall_arrayref({}) || undef;

                if ($returning_aref && (scalar @$returning_aref)) {
                    if ($DBI::errstr) {
                        my $error_message = $DBI::errstr;
                        $error_message =~ s/\s+$//;

                        if (&nolog ($stm, $error_message)) {
                            &Jarvis::Error::debug ($jconfig, "Failure fetching first return result set. Log disabled.");
                        } else {
                            &Jarvis::Error::log ($jconfig, "Failure fetching first return result set for '" . $stm->{ttype} . "'.  Details follow.");
                            &Jarvis::Error::log ($jconfig, $stm->{sql_with_substitutions}) if $stm->{sql_with_substitutions};
                            &Jarvis::Error::log ($jconfig, $error_message);
                            &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) || 'NONE'));
                        }

                        $stm->{sth}->finish;
                        $stm->{error} = $error_message;
                        $row_result->{success} = 0;
                        $row_result->{message} = $error_message;

                    # Successful returning?  See if we can get type information?
                    } else {
                        my $column_names_aref = $stm->{sth}{NAME};
                        $returning_types = &get_column_types ($jconfig, $column_names_aref, $dbh, $stm->{sth});
                    }

                    $row_result->{returning} = $returning_aref;
                    &Jarvis::Error::debug ($jconfig, "Fetched " . (scalar @$returning_aref) . " rows for returning.");

                    # Now transform using the same behavior as for fetch.
                }

                # When using output parameters from a SQL Server stored procedure, there is a
                # difference of behavior between Linux/FreeTDS and Windows/ODBC.  Under Linux you
                # always get a result set containing the output parameters, with autogenerated
                # column names prefixed by underscore.
                #
                # Under Windows you need to explicitly do a SELECT to get this and you must
                # specify the column names.
                #
                # This leads to the case where to write a dataset that works under both Linux
                # and Windows, you need to explicitly SELECT (so that you get the data under
                # Windows, and make sure that the column name you select AS is identical to the
                # auto-generated name created by FreeTDS).
                #
                # However, under Linux that means you get two result sets.  If you pass more than
                # one <row> in your request, then the second row will fail with
                # "Attempt to initiate a new Adaptive Server operation with results pending"
                #
                # To avoid that error, here we will look to see if there are any extra result
                # sets now pending to be read.  We will silently read and discard them.
                #
                while ($row_result->{success} && $stm->{sth}{syb_more_results}) {
                    &Jarvis::Error::debug ($jconfig, "Found additional result sets.  Fetch and discard.");
                    $stm->{sth}->fetchall_arrayref ({});

                    if ($DBI::errstr) {
                        my $error_message = $DBI::errstr;
                        $error_message =~ s/\s+$//;

                        if (&nolog ($stm, $error_message)) {
                            &Jarvis::Error::debug ($jconfig, "Failure fetching additional result sets. Log disabled.");

                        } else {
                            &Jarvis::Error::log ($jconfig, "Failure fetching additional result sets for '" . $stm->{ttype} . "'.  Details follow.");
                            &Jarvis::Error::log ($jconfig, $stm->{sql_with_substitutions}) if $stm->{sql_with_substitutions};
                            &Jarvis::Error::log ($jconfig, $error_message);
                            &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) || 'NONE'));
                        }

                        $stm->{sth}->finish;
                        $stm->{error} = $error_message;
                        $row_result->{success} = 0;
                        $row_result->{message} = $error_message;
                    }
                }
            }

            # This is disappointing, but perhaps a "die" is too strong here.
            if (! $row_result->{returning}) {
                &Jarvis::Error::debug ($jconfig, "Cannot determine how to get values for 'returning' statement.");
            }
        }


    }

    return ($row_result, $returning_types);
}

################################################################################
# Free any statements or other resources that we might have allocated.
#
# Params:
#       $class - Agent classname.
#       $jconfig - Jarvis::Config object
#       $dbh - Database handle of the correct type to match the dataset.
#       $stms - Hash of pre-prepared statements by row type.
#
# Returns:
#       undef
################################################################################
sub free_statements {
    my ($class, $jconfig, $dbh, $stms) = @_;

    foreach my $stm_type (keys (%$stms)) {
        &Jarvis::Error::debug ($jconfig, "Finished with statement for ttype '$stm_type'.");
        $stms->{$stm_type}{sth}->finish;
    }

    return undef;
}

################################################################################
# Execute the "after" statement for a dataset.  This a once-only statement
# that occurs prior to any row updates.
#
# Params:
#       $class - Agent classname.
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in MDX
#               username            Used for {{username}} in MDX
#               group_list          Used for {{group_list}} in MDX
#               format              Either "json" or "xml" or "csv".
#
#       $dataset_name - Name of single dataset we are fetching from.
#       $dsxml - Dataset's XML configuration object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $after_params_href - All our after parameters parameters.
#
# Returns:
#       undef on success, "Error Text" on failure.
################################################################################
sub execute_after {
    my ($class, $jconfig, $dataset_name, $dsxml, $dbh, $after_params_href) = @_;

    my $astm = &parse_statement ($jconfig, $dataset_name, $dsxml, $dbh, 'after', $after_params_href);
    if ($astm) {
        my @aarg_values = &Jarvis::Dataset::names_to_values ($jconfig, $astm->{vnames_aref}, $after_params_href);

        &statement_execute($jconfig, $astm, \@aarg_values);
        if ($astm->{error}) {
            my $message = $astm->{error};
            $message =~ s/^Server message number=[0-9]+ severity=[0-9]+ state=[0-9]+ line=[0-9]+ server=[A-Z0-9\\]+text=//i;
            return $message;
        }
    }

    return undef;
}

1;
