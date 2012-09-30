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

package Jarvis::Dataset::DBI;

use DBI;
use JSON::PP; 
use XML::Smart;
use Data::Dumper;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;
use Jarvis::Hook;

use sort 'stable';      # Don't mix up records when server-side sorting

################################################################################
# Get the SQL for the update, insert, and delete or whatever.
#
# Params:
#       $jconfig - Jarvis::Config object (NOT USED YET)
#       $which   - SQL Type ("select", "insert", "update", "delete")
#       $dsxml   - XML::Smart object for dataset configuration
#
# Returns:
#       $raw_sql
#       die on error.
################################################################################
#
sub get_sql {
    my ($jconfig, $which, $dsxml) = @_;

    my $raw_sql = $dsxml->{dataset}{$which}->content || return undef;
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
#       ($sql_with_substitutions, @variable_names).
################################################################################
#
sub sql_with_substitutions {

    my ($jconfig, $dbh, $sql, $args_href) = @_;

    # Dump the available arguments at this stage.
    foreach my $k (keys %{$args_href}) {
        &Jarvis::Error::dump ($jconfig, "SQL available args: '$k' -> " . (defined $args_href->{$k} ? '"' . $args_href->{$k} . '"' : '<NULL>') . ".");
    }
    
    # Parse the update SQL to get a prepared statement, pulling out the list
    # of names of {{variables}} we replaced by ?.
    #
    # Parameters NAMES may contain only a-z, A-Z, 0-9, underscore(_), colon(:) and hyphen(-)
    # Note pipe(|) is also allowed at this point as it separates (try-else variable names)
    my $sql2 = "";
    my @bits = split (/\{\{?\$?([a-zA-Z0-9_\-:\|]+)\}\}?/i, $sql);
    my @variable_names = ();

    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $name = $bits[$idx];
            push (@variable_names, $name);
            $sql2 .= "?";

        } else {
            $sql2 .= $bits[$idx];
        }
    }

    # Now perform any textual substitution of [[ ]] variables.  Note that
    # this really only makes sense with FETCH statements, and with rest
    # args in store statements.
    #
    # Parameters NAMES may contain only a-z, A-Z, 0-9, underscore(_), colon(:) and hyphen(-)
    # Note pipe(|) is also allowed at this point as it separates (try-else variable names)
    #
    @bits = split (/\[[\[\$]([a-zA-Z0-9_\-:\|]+(?:\![a-z]+)*)\]\]?/i, $sql2);

    my $sql3 = "";
    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $name = $bits[$idx];
            my %flags = ();

            # Flags may be specified after the variable name with a colon separating the variable
            # name and the flag.  Multiple flags are permitted in theory, with a colon before
            # each flag.  Supported flags at this stage are:
            #
            #   !noquote        Don't wrap strings with quotes, instead just restrict content.
            #   !quote          Always quote, even for numbers.
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
                $value = $args_href->{$option};
                last if (defined $value);
            }
            (defined $value) || ($value = '');

            # Numeric values by default are NOT quoted, unless requested.
            if ($value =~ m/^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/ && ! $flags{'quote'}) {
                # No change.

            # Raw flag performs NO changes ever!  Only allowed for SAFE variables (not client-supplied). 
            } elsif ($flags{'raw'} && ($name =~ m/^__/)) {
                # No change.
                
            } elsif ($flags{'noquote'}) {
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

    return ($sql3, @variable_names);
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
#               {'ttype'}
#               {'raw_sql'}
#               {'sql_with_substitutions'}
#               {'returning'}
#               {'sth'}
#               {'vnames_aref'}
#               {'error'}      (Set later, to error message from latest action)
#               {'retval'}     (Set later, return value of latest action)
#
#       Or undef if no SQL.
################################################################################
#
sub parse_statement {
    my ($jconfig, $dsxml, $dbh, $ttype, $args_href) = @_;

    my $obj = {};

    # Get and check the raw SQL, before parameter -> ? substitution.
    &Jarvis::Error::debug ($jconfig, "Parsing statement for transaction type '$ttype'");
    $obj->{'ttype'} = $ttype;
    $obj->{'raw_sql'} = &get_sql ($jconfig, $ttype, $dsxml);
    if (! $obj->{'raw_sql'}) {
        &Jarvis::Error::debug ($jconfig, "No SQL found for type '$ttype'");
        return undef;
    }
    &Jarvis::Error::dump ($jconfig, "SQL as read from XML = " . $obj->{'raw_sql'});

    # Does this insert return rows?
    $obj->{'returning'} = defined ($Jarvis::Config::yes_value {lc ($dsxml->{dataset}{$ttype}{'returning'} || "no")});
    &Jarvis::Error::debug ($jconfig, "Returning? = " . $obj->{'returning'});

    # Get our SQL with placeholders and prepare it.
    my ($sql_with_substitutions, @variable_names) = &sql_with_substitutions ($jconfig, $dbh, $obj->{'raw_sql'}, $args_href);
    $obj->{'sql_with_substitutions'} = $sql_with_substitutions;
    $obj->{'vnames_aref'} = \@variable_names;

    &Jarvis::Error::dump ($jconfig, "SQL after substition = " . $sql_with_substitutions);

    # get db-specific parameters
    my $dbxml = &Jarvis::DB::db_config($jconfig, $dsxml->{dataset}{'dbname'}, $dsxml->{dataset}{'dbtype'});

    # Use special prepare parameters
    my $db_prepare_str = $dbxml->{'prepare'};
    my $ds_prepare_str = $dsxml->{dataset}{$ttype}{'prepare'};
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
        $obj->{'sth'} = $dbh->prepare ($sql_with_substitutions, \%prepare_attr) ||
            die "Couldn't prepare statement for $ttype on '" . $jconfig->{'dataset_name'} . "'.\nSQL ERROR = '" . $dbh->errstr . "'.";
    }

    # Log suppression pattern
    $obj->{'nolog'} = ($dsxml->{dataset}{$ttype}{'nolog'}||'');
    # Warning/error suppression pattern
    $obj->{'ignore'} = ($dsxml->{dataset}{$ttype}{'ignore'}||'');

    return $obj;
}

################################################################################
# check if error message should be supressed due to nolog flag
# 
# Params:
#       stm - statement object as returned by parse_statement
#       message - error message to match against nolog flag
#
# Returns:
#       1 if message matches nolog flag
#       0 otherwise
################################################################################
sub nolog {
    my ($stm, $message) = @_;

    my $nolog = $stm->{'nolog'};
    if ($nolog && $message =~ /$nolog/) {
        return 1;
    } else {
        return 0;
    }
}

################################################################################
# check if error message should be supressed due to ignore flag
# 
# Params:
#       stm - statement object as returned by parse_statement
#       message - error message to match against ignore flag
#
# Returns:
#       1 if message matches ignore flag
#       0 otherwise
################################################################################
sub ignore {
    my ($stm, $message) = @_;

    my $ignore = $stm->{'ignore'};
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
    my ($jconfig, $stm, $arg_values_aref) = @_;

    my $err_handler = $SIG{__DIE__};
    $stm->{'retval'} = 0;
    $stm->{'error'} = undef;
    eval {
        no warnings 'uninitialized';
        $SIG{__DIE__} = sub {};
        $stm->{'retval'} = $stm->{'sth'}->execute (@$arg_values_aref);
    };
    $SIG{__DIE__} = $err_handler;

    my $error_message = $stm->{'sth'}->errstr || $@ || $DBI::errstr;
    if (($error_message && !ignore($stm, $error_message)) || (!defined $stm->{'retval'})) {
        # ensure we have an error message to return
        $error_message = $error_message || 'Unknown error SQL execution error.';
        $error_message =~ s/\s+$//;

        if (&nolog($stm, $error_message)) {
            &Jarvis::Error::debug ($jconfig, "Failure executing SQL. Log disabled.");
        } else {
            &Jarvis::Error::log ($jconfig, "Failure executing SQL for '" . $stm->{'ttype'} . "'.  Details follow.");
            &Jarvis::Error::log ($jconfig, $stm->{'sql_with_substitutions'}) if $stm->{'sql_with_substitutions'};
            &Jarvis::Error::log ($jconfig, $error_message);
            &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @$arg_values_aref) || 'NONE'));
        }

        $stm->{'sth'}->finish;
        $stm->{'error'} = $error_message;
        return 0;
    }

    &Jarvis::Error::debug ($jconfig, 'Successful statement execution.  RetVal = ' . $stm->{'retval'});
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
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#
#       $subset_name - Name of single dataset we are fetching from.
#       $dsxml - Dataset's XML configuration object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $safe_params_href - All our safe parameters.
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
################################################################################
#
sub fetch {
    my ($jconfig, $subset_name, $dsxml, $dbh, $safe_params_href) = @_;
    
    # Get our STM.  This has everything attached.
    my $stm = &parse_statement ($jconfig, $dsxml, $dbh, 'select', $safe_params_href) ||
        die "Dataset '$subset_name' has no SQL of type 'select'.";

    # Convert the parameter names to corresponding values.
    my @arg_values = &Jarvis::Dataset::names_to_values ($jconfig, $stm->{'vnames_aref'}, $safe_params_href);

    # Execute Select, return on error
    &statement_execute($jconfig, $stm, \@arg_values);
    $stm->{'error'} && die $stm->{'error'};

    # Fetch the data.
    my $rows_aref = $stm->{'sth'}->fetchall_arrayref({});
    
    # See if we can get column names.  If we can't get them legitimately 
    # then try sniffing them from the results, though we will lose any column
    # ordering that might have otherwise existed in the original query.
    my $column_names_aref = $stm->{'sth'}->{NAME}; 
    if ((scalar @$rows_aref) && ! $column_names_aref) {
        &Jarvis::Error::debug ($jconfig, 'No column names from query.  Try sniffing results.');
        my @column_names = sort (keys (%{ $$rows_aref[0] }));
        $column_names_aref = \@column_names;
    }
    
    # Finish the statement handle.
    $stm->{'sth'}->finish;

    return ($rows_aref, $column_names_aref); 
}

################################################################################
# Performs an update to the specified table underlying the named dataset.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               format              Either "json" or "xml" (not "csv").
#
#       $subset_name - Name of single dataset we are storing to.
#       $dsxml - Dataset XML object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub store {
    my ($jconfig, $subset_name, $dsxml, $dbh, $rest_args_aref) = @_;

    # What transforms should we use when processing store data?
    my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->{dataset}{transform}{store});
    &Jarvis::Error::debug ($jconfig, "Store transformations = " . join (', ', keys %transforms) . " (applied to incoming row data)");

    # Get our submitted content
    my $content = &Jarvis::Dataset::get_post_data ($jconfig);
    $content || die "No content body to store";
    &Jarvis::Error::debug ($jconfig, "Request Content Length = " . length ($content));
    &Jarvis::Error::dump ($jconfig, $content);

    # Fields we need to store.  This is an ARRAY ref to multiple rows each a HASH REF
    my $fields_aref = undef;

    # Check we have some changes and parse 'em from the JSON.  We get an
    # array of hashes.  Each array entry is a change record.
    my $return_array = 0;
    my $content_type = $jconfig->{'cgi'}->content_type () || '';

    &Jarvis::Error::debug ($jconfig, "Request Content Type = '" . $content_type . "'");
    if ($content_type =~ m|^[a-z]+/json(; .*)?$|) {
        my $ref = JSON::PP->new->utf8->decode ($content);

        # User may pass a single hash record, OR an array of hash records.  We normalise
        # to always be an array of hashes.
        if (ref $ref eq 'HASH') {
            my @fields = ($ref);
            $fields_aref = \@fields;

        } elsif (ref $ref eq 'ARRAY') {
            $return_array = 1;
            $fields_aref = $ref;

        } else {
            die "Bad JSON ref type " . (ref $ref);
        }

    # XML in here please.
    } elsif ($content_type =~ m|^[a-z]+/xml(; .*)?$|) {
        my $cxml = XML::Smart->new ($content);

        # Sanity check on outer object.
        $cxml->{'request'} || die "Missing top-level 'request' element in submitted XML content.\n";

        # Fields may either sit at the top level, or you may provide an array of
        # records in a <row> array.
        #
        my @rows = ();
        if ($cxml->{'request'}{'row'}) {
            foreach my $row (@{ $cxml->{'request'}{'row'} }) {
                my %fields =%{ $row };
                push (@rows, \%fields);
            }
            $return_array = 1;

        } else {
            my %fields = %{ $cxml->{'request'} };
            push (@rows, \%fields);
        }
        $fields_aref = \@rows;

    # Unsupported format.
    } else {
        die "Unsupported content type for changes: '$content_type'\n";
    }

    # Store this for tracking
    $jconfig->{'in_nrows'} = scalar @$fields_aref;

    # Choose our statement and find the SQL and variable names.
    my $ttype = $jconfig->{'action'};
    &Jarvis::Error::debug ($jconfig, "Transaction Type = '$ttype'");
    ($ttype eq "delete") || ($ttype eq "update") || ($ttype eq "insert") || ($ttype eq "mixed") ||
        die "Unsupported transaction type '$ttype'.";

    # Shared database handle.
    $dbh->begin_work() || die;

    # Loop for each set of updates.
    my $success = 1;
    my $modified = 0;
    my @results = ();
    my $message = '';

    # We pre-compute the "before" statement parameters even if there is no before statement,
    # since we may also wish to log them.
    my %restful_params = &Jarvis::Config::safe_variables ($jconfig, {}, $rest_args_aref);
    my %params_copy = %restful_params;
    $jconfig->{'params_href'} = \%params_copy;

    # Invoke before_all hook.
    &Jarvis::Hook::before_all ($jconfig, $dsxml, \%restful_params, $fields_aref);

    # Execute our "before" statement.  This statement is NOT permitted to fail.  If it does,
    # then we immediately barf
    {
        my $bstm = &parse_statement ($jconfig, $dsxml, $dbh, 'before', \%params_copy);
        if ($bstm) {
            my @barg_values = &Jarvis::Dataset::names_to_values ($jconfig, $bstm->{'vnames_aref'}, \%restful_params);

            &statement_execute($jconfig, $bstm, \@barg_values);
            if ($bstm->{'error'}) {
                $success = 0;
                $message || ($message = $bstm->{'error'});
            }
        }
    }

    # Our cached statement handle(s).
    my %stm = ();

    # Handle each insert/update/delete request row.
    foreach my $fields_href (@$fields_aref) {

        # Stop as soon as anything goes wrong.
        if (! $success) {
            &Jarvis::Error::debug ($jconfig, "Error detected.  Stopping.");
            last;
        }

        # Handle our parameters.  Always with placeholders.  Note that our special variables
        # like __username are safe, and cannot come from user-defined values.
        #
        my %raw_params = %{ $fields_href };
        my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%raw_params, $rest_args_aref);

        # Store these new parameters for our tracking purposes.
        %params_copy = %safe_params;
        $jconfig->{'params_href'} = \%params_copy;

        # Any input transformations?
        if (scalar (keys %transforms)) {
            &Jarvis::Dataset::transform (\%transforms, \%safe_params);
        }

        # Invoke before_one hook.
        &Jarvis::Hook::before_one ($jconfig, $dsxml, \%safe_params);

        # Figure out which statement type we will use for this row.
        my $row_ttype = $safe_params{'_ttype'} || $ttype;
        ($row_ttype eq 'mixed') && die "Transaction Type 'mixed', but no '_ttype' field present in row.";

        # Get the statement type for this ttype if we don't have it.  This raises debug.
        if (! $stm{$row_ttype}) {
            $stm{$row_ttype} = &parse_statement ($jconfig, $dsxml, $dbh, $row_ttype, \%params_copy);
        }

        # Check we have an stm for this row.
        my $stm = $stm{$row_ttype} ||
            die "Dataset '$subset_name' has no SQL of type '$row_ttype'.";

        # Determine our argument values.
        my @arg_values = &Jarvis::Dataset::names_to_values ($jconfig, $stm->{'vnames_aref'}, \%safe_params);

        # Execute
        my %row_result = ();
        my $stop = 0;
        my $num_rows = 0;

        &statement_execute ($jconfig, $stm, \@arg_values);
        $row_result{'modified'} = $stm->{'retval'} || 0;
        $modified = $modified + $row_result{'modified'};

        # On failure, we will still return valid JSON/XML to the caller, but we will indicate
        # which request failed and will send back an overall "non-success" flag.
        #
        if ($stm->{'error'}) {
            $row_result{'success'} = 0;
            $row_result{'modified'} = 0;
            $row_result{'message'} = $stm->{'error'};
            $success = 0;
            $message || ($message = $stm->{'error'});

            # Log the error in our tracker database.
            unless (&nolog($stm, $stm->{'error'})) {
                &Jarvis::Tracker::error ($jconfig, '200', $stm->{'error'});
            }

        # Suceeded.  Set per-row status, and fetch the returned results, if this
        # operation indicates that it returns values.
        #
        } else {
            $row_result{'success'} = 1;

            # Try and determine the returned values (normally the auto-increment ID)
            if ($stm->{'returning'}) {

                # See if the query had a built-in fetch.  Under PostGreSQL (and very
                # likely also under other drivers) this will fail if there is no current
                # query.  I.e. if you have no "RETURNING" clause on your insert.
                #
                # However, under SQLite, this appears to be forgiving if there is no
                # RETURNING clause.  SQLite doesn't have a RETURNING clause, but it will
                # quietly return no data, allowing us to have a second try just below.
                #
                my $returning_aref = $stm->{'sth'}->fetchall_arrayref({}) || undef;

                if ($returning_aref && (scalar @$returning_aref)) {
                    if ($DBI::errstr) {
                        my $error_message = $DBI::errstr;
                        $error_message =~ s/\s+$//;

                        if (&nolog($stm, $error_message)) {
                            &Jarvis::Error::debug ($jconfig, "Failure fetching first return result set. Log disabled.");
                        } else {
                            &Jarvis::Error::log ($jconfig, "Failure fetching first return result set for '" . $stm->{'ttype'} . "'.  Details follow.");
                            &Jarvis::Error::log ($jconfig, $stm->{'sql_with_substitutions'}) if $stm->{'sql_with_substitutions'};
                            &Jarvis::Error::log ($jconfig, $error_message);
                            &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) || 'NONE'));
                        }

                        $stm->{'sth'}->finish;
                        $stm->{'error'} = $error_message;
                        $success = 0;
                        $message = $error_message;

                        # Log the error in our tracker database.
                        unless (&nolog($stm, $error_message)) {
                            &Jarvis::Tracker::error ($jconfig, '200', $error_message);
                        }
                    }

                    $row_result{'returning'} = $returning_aref;
                    $jconfig->{'out_nrows'} = scalar @$returning_aref;
                    &Jarvis::Error::debug ($jconfig, "Fetched " . (scalar @$returning_aref) . " rows for returning.");


                # Hmm... we're supposed to be returning data, but the query didn't give
                # us any.  Interesting.  Maybe it's SQLite?  In that case, we need to
                # go digging for the return values via last_insert_rowid().
                #
                } elsif ($row_ttype eq 'insert') {
                    if ($jconfig->{'xml'}{'jarvis'}{'app'}{'database'}{'connect'}->content =~ m/^dbi:SQLite:/) {
                        my $rowid = $dbh->func('last_insert_rowid');
                        if ($rowid) {
                            my %return_values = %safe_params;
                            $return_values {'id'} = $rowid;

                            $row_result{'returning'} = [ \%return_values ];
                            $jconfig->{'out_nrows'} = 1;
                        }
                        &Jarvis::Error::debug ($jconfig, "Used SQLite last_insert_rowid to get returned 'id' => '$rowid'.");
                    }
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
                while ($success && $stm->{'sth'}->{syb_more_results}) {
                    &Jarvis::Error::debug ($jconfig, "Found additional result sets.  Fetch and discard.");
                    $stm->{'sth'}->fetchall_arrayref ({});

                    if ($DBI::errstr) {
                        my $error_message = $DBI::errstr;
                        $error_message =~ s/\s+$//;

                        if (&nolog($stm, $error_message)) {
                            &Jarvis::Error::debug ($jconfig, "Failure fetching additional result sets. Log disabled.");
                        } else {
                            &Jarvis::Error::log ($jconfig, "Failure fetching additional result sets for '" . $stm->{'ttype'} . "'.  Details follow.");
                            &Jarvis::Error::log ($jconfig, $stm->{'sql_with_substitutions'}) if $stm->{'sql_with_substitutions'};
                            &Jarvis::Error::log ($jconfig, $error_message);
                            &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) || 'NONE'));
                        }

                        $stm->{'sth'}->finish;
                        $stm->{'error'} = $error_message;
                        $success = 0;
                        $message = $error_message;
                    }
                }

                # This is disappointing, but perhaps a "die" is too strong here.
                if (! $row_result{'returning'}) {
                    &Jarvis::Error::debug ($jconfig, "Cannot determine how to get returning values.");
                }
            }
        }

        # Invoke after_one hook.
        if ($success) {
            &Jarvis::Hook::after_one ($jconfig, $dsxml, \%safe_params, \%row_result);
        }

        push (@results, \%row_result);
    }

    # Reset our parameters, our per-row parameters are no longer valid.
    %params_copy = %restful_params;
    $jconfig->{'params_href'} = \%params_copy;

    # Free any remaining open statement types.
    foreach my $stm_type (keys %stm) {
        &Jarvis::Error::debug ($jconfig, "Finished with statement for ttype '$stm_type'.");
        $stm{$stm_type}->{'sth'}->finish;
    }

    # Execute our "after" statement.
    if ($success) {
        my $astm = &parse_statement ($jconfig, $dsxml, $dbh, 'after', \%params_copy);
        if ($astm) {
            my @aarg_values = &Jarvis::Dataset::names_to_values ($jconfig, $astm->{'vnames_aref'}, \%restful_params);

            &statement_execute($jconfig, $astm, \@aarg_values);
            if ($astm->{'error'}) {
                $success = 0;
                $message || ($message = $astm->{'error'});
            }
        }
        &Jarvis::Hook::after_all ($jconfig, $dsxml, \%restful_params, $fields_aref, \@results);
    }

    # Determine if we're going to rollback.
    if (! $success) {
        &Jarvis::Error::debug ($jconfig, "Error detected.  Rolling back.");

        # Use "eval" as some drivers (e.g. SQL Server) will have already rolled-back on the
        # original failure, and hence a second rollback will fail.
        eval { local $SIG{'__DIE__'}; $dbh->rollback (); }

    } else {
        &Jarvis::Error::debug ($jconfig, "All successful.  Committing all changes.");
        $dbh->commit ();
    }

    # Return content in requested format.
    &Jarvis::Error::debug ($jconfig, "Return Array = $return_array.");

    # Cleanup SQL Server message for reporting purposes.
    $message =~ s/^Server message number=[0-9]+ severity=[0-9]+ state=[0-9]+ line=[0-9]+ server=[A-Z0-9\\]+text=//i;

    # Store some additional info in jconfig just in case the hook needs it.
    $jconfig->{'return_array'} = $return_array;
    $jconfig->{'success'} = $success;
    $jconfig->{'message'} = $message;
    $jconfig->{'modified'} = $modified;

    # This final hook allows you to do whatever you want to modify the returned
    # data.  This hook may do one or both of:
    #
    #   - Completely modify the returned content (by modifying \@results)
    #   - Peform a custom encoding into text (by setting $return_text)
    #
    my $extra_href = {};
    my $return_text = undef;
    &Jarvis::Hook::return_store ($jconfig, $dsxml, \%restful_params, $fields_aref, \@results, $extra_href, \$return_text);

    # If the hook set $return_text then we use that.
    if ($return_text) {
        &Jarvis::Error::debug ($jconfig, "Return content determined by hook ::return_store");

    # Otherwise we encode to a supported format.  Note that the hook may have modified
    # the data prior to this encoding.
    #
    # Note here that our return structure is different depending on whether you handed us
    # just one record (not in an array), or if you gave us an array of records.  An array
    # containing one record is NOT the same as a single record not in an array.
    #
    } elsif ($jconfig->{'format'} =~ m/^json/) {
        my %return_data = ();
        $return_data {'success'} = $success;
        $success && ($return_data {'modified'} = $modified);
        $success || ($return_data {'message'} = &trim($message));
        foreach my $name (sort (keys %$extra_href)) {
            $return_data {$name} = $extra_href->{$name};
        }

        # Return the array data if we succeded.
        if ($success && $return_array) {
            $return_data {'row'} = \@results;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $results[0]{'returning'} && ($return_data {'returning'} = $results[0]{'returning'});
        }
        my $json = JSON::PP->new->pretty(1);
        $return_text = $json->encode ( \%return_data );

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{'response'}{'success'} = $success;
        $success && ($xml->{'response'}{'modified'} = $modified);
        $success || ($xml->{'response'}{'message'} = &trim($message));
        foreach my $name (sort (keys %$extra_href)) {
            $xml->{'response'}{$name} = $extra_href->{$name};
        }

        # Return the array data if we succeeded.
        if ($success && $return_array) {
            $xml->{'response'}{'results'}->{'row'} = \@results;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $results[0]{'returning'} && ($xml->{'response'}{'returning'} = $results[0]{'returning'});
        }
        $return_text = $xml->data ();

    } else {
        die "Unsupported format '" . $jconfig->{'format'} ."' for Dataset::store return data.\n";
    }

    &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($return_text));
    &Jarvis::Error::dump ($jconfig, $return_text);
    return $return_text;
}

1;
