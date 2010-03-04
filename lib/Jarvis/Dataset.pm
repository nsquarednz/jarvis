###############################################################################
# Description:  Dataset access functions.  This is the core purpose of Jarvis,
#               to provide a front end to your database so that your ExtJS,
#               Adobe Flex, or other web application can have simple JSON or
#               XML web-service access to fetch and update data from your
#               back end SQL database on the server.
#
#               A dataset is defined by a <dataset>.xml file which contains
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

use DBI;
use JSON::PP;           # JSON::PP was giving double-free/corruption errors.
use XML::Smart;
use Text::CSV;
use IO::String;

package Jarvis::Dataset;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;

use sort 'stable';      # Don't mix up records when server-side sorting

###############################################################################
# Internal Functions
###############################################################################

################################################################################
# Loads the DataSet config from the config dir and returns it as XML.
#
#       $jconfig - Jarvis::Config object
#           READ
#               xml                 Find our app-configured "dataset_dir" dir.
#               dataset_name        What dataset do we want?
#           WRITE
#               page_start_param    Name of the CGI param specifying page start row num
#               page_limit_param    Name of the CGI param specifying page limit row num
#               sort_field_param    Name of the CGI param specifying page sort field
#               sort_dir_param      Name of the CGI param specifying page sort direction
#
#   Note that a "." in a dataset name is a directory path.  Note that the
#   caller may NOT ever specify the ".xml" suffix, since we would confuse
#   "test.xml" for "<dataset_dir>/test/xml.xml".  And that would be bad.
#
#   Note that it is OUR job to check that the path is safe before opening
#   the file.
#
# Returns:
#       $dsxml - XML::Smart object holding config info read from file.
################################################################################
#
sub get_config_xml {
    my ($jconfig) = @_;

    my $cgi = $jconfig->{"cgi"};

    # And this MUST contain our dataset dir.
    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    my $dataset_dir = $axml->{'dataset_dir'}->content ||
        die "No attribute 'dataset_dir' configured.";
    &Jarvis::Error::debug ($jconfig, "Dataset Directory '$dataset_dir'.");

    # Determine the raw dataset name, before "." translation.
    my $dataset_name = $jconfig->{'dataset_name'};
    &Jarvis::Error::debug ($jconfig, "Dataset Name '$dataset_name' (as supplied).");

    ($dataset_name =~ m/^\./) && die "Leading '.' not permitted on dataset name '$dataset_name'";
    ($dataset_name =~ m/\.$/) && die "Trailing '.' not permitted on dataset name '$dataset_name'";

    $dataset_name =~ s/\./\//g;

    # Load the dataset-specific XML file and double-check it has top-level <dataset> tag.
    my $dsxml_filename = "$dataset_dir/$dataset_name.xml";
    &Jarvis::Error::debug ($jconfig, "Opening DSXML file '$dsxml_filename'.");

    # Check it exists.
    if (! -f $dsxml_filename) {
        $jconfig->{'status'} = '404 Not Found';
        die "No such DSXML file '$dataset_name.xml' for application '" . $jconfig->{'app_name'} . "'";
    }

    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # Enable per dataset dump/debug
    $jconfig->{'dump'} = $jconfig->{'dump'} || defined ($Jarvis::Config::yes_value {lc ($dsxml->{'dataset'}{'dump'}->content || "no")});
    $jconfig->{'debug'} = $jconfig->{'dump'} || defined ($Jarvis::Config::yes_value {lc ($dsxml->{'dataset'}{'debug'}->content || "no")});

    # Load a couple of other parameters.  This is a "side-effect".  Yeah, it's a bit yucky.
    $jconfig->{'page_start_param'} = lc ($axml->{'page_start_param'}->content || 'page_start');
    $jconfig->{'page_limit_param'} = lc ($axml->{'page_limit_param'}->content || 'page_limit');
    $jconfig->{'sort_field_param'} = lc ($axml->{'sort_field_param'}->content || 'sort_field');
    $jconfig->{'sort_dir_param'} = lc ($axml->{'sort_dir_param'}->content || 'sort_dir');

    return $dsxml;
}

################################################################################
# Get the SQL for the update, insert, and delete or whatever.
#
# Params:
#       $jconfig - Jarvis::Config object (NOT USED YET)
#       $which   - SQL Type ("fetch", "insert", "update", "delete")
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
# Expand the SQL, replace args with ?, and return list of arg names.
#
# Params:
#       SQL text.
#
# Returns:
#       ($sql_with_placeholders, @variable_names).
################################################################################
#
sub sql_with_placeholders {

    my ($sql) = @_;

    # Parse the update SQL to get a prepared statement, pulling out the list
    # of names of variables we need to replace for each execution.
    my $sql_with_placeholders = "";
    my @bits = split (/\{\{?\$?([^\}]+)\}\}?/i, $sql);
    my @variable_names = ();

    my $num_params = 0;
    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            push (@variable_names, $bits[$idx]);
            $sql_with_placeholders .= "?";

        } else {
            $sql_with_placeholders .= $bits[$idx];
        }
    }

    return ($sql_with_placeholders, @variable_names);
}

################################################################################
# Take an array of variable names, and substitute a value for each one from
# our hash of name -> value parameters.  The variable names come from {{name}},
# and may include a series of names, e.g. {{id|1}} which means:
#
#       - Use a supplied user parameter "id" if it exists.
#       - If no "id", try REST parameter #1.  E.g /<app>/<dataset>/<id>
#       - If no rest parameter, use NULL
#
# Params:
#       $variable_names_aref - Array of variable names.
#       $safe_params_href - Hash of name -> values.
#
# Returns:
#       @arg_values
#       die on error.
################################################################################
#
sub names_to_values {
    my ($jconfig, $variable_names_aref, $safe_params_href) = @_;

    my @arg_values = ();
    foreach my $name (@$variable_names_aref) {
        my $value = undef;
        foreach my $option (split ('\|', $name)) {
            $value = $$safe_params_href {$option};
            last if (defined $value);
        }
        push (@arg_values, $value);
    }
    &Jarvis::Error::debug ($jconfig, "VARS = " . join (",", @$variable_names_aref));
    &Jarvis::Error::debug ($jconfig, "ARGS = " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values));
    return @arg_values;
}

################################################################################
# Perform some optional server-side data transforms.  These are configured
# by e.g.
#       <dataset>
#           <transform store="trim,null" fetch="notnull" />
#           <select> ...
#
# Options are:
#       trim - Leading and trailing whitespace is removed.
#       null - All whitespace/empty strings are converted to NULL/absent.
#       notnull - All NULL strings are converted to ''.
#
# Params:
#       $transforms_href - Hash of 'enabled-option' -> 1
#       $vals_href - Hash of key -> value to transform
#
# Returns:
#       1
################################################################################
#
sub transform {
    my ($transforms_href, $vals_href) = @_;

    # Trim leading and trailing space off any defined value.
    if ($$transforms_href{'trim'}) {
        foreach my $key (keys %$vals_href) {
            next if ! defined $$vals_href{$key};
            $$vals_href{$key} = &trim ($$vals_href{$key});
        }
    }

    # Convert any whitespace values into undef.  Later, all undef values
    # will be omitted from the final results in JSON and XML format.
    if ($$transforms_href{'null'}) {
        foreach my $key (keys %$vals_href) {
            next if ! defined $$vals_href{$key};
            if ($$vals_href{$key} =~ m/^\s*$/) {
                $$vals_href{$key} = undef;
            }
        }
    }

    # Any undef values will be converted to whitespace.
    if ($$transforms_href{'notnull'}) {
        foreach my $key (keys %$vals_href) {
            (defined $$vals_href{$key}) || ($$vals_href{$key} = '');
        }
    }
    return 1;
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
#
# Returns:
#       STM hash with keys
#               {'ttype'}
#               {'raw_sql'}
#               {'sql_with_placeholders'}
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
    my ($jconfig, $dsxml, $dbh, $ttype) = @_;

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
    my ($sql_with_placeholders, @variable_names) = &sql_with_placeholders ($obj->{'raw_sql'});
    $obj->{'sql_with_placeholders'} = $sql_with_placeholders;
    $obj->{'vnames_aref'} = \@variable_names;

    # Do the prepare, with RaiseError & PrintError disabled.
    {
        local $dbh->{RaiseError};
        local $dbh->{PrintError};
        $obj->{'sth'} = $dbh->prepare ($sql_with_placeholders) ||
            die "Couldn't prepare statement for $ttype on '" . $jconfig->{'dataset_name'} . "'.\nSQL ERROR = '" . $dbh->errstr . "'.";
    }

    return $obj;
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

    if ($@ || $DBI::errstr || (! defined $stm->{'retval'})) {
        my $error_message = $stm->{'sth'}->errstr || $@ || 'Unknown error SQL execution error.';
        $error_message =~ s/\s+$//;

        &Jarvis::Error::log ($jconfig, "Failure executing SQL for '" . $stm->{'ttype'} . "'.  Details follow.");
        &Jarvis::Error::log ($jconfig, $stm->{'sql_with_placeholders'}) if $stm->{'sql_with_placeholders'};
        &Jarvis::Error::log ($jconfig, $error_message);
        &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @$arg_values_aref) || 'NONE'));

        $stm->{'sth'}->finish;
        $stm->{'error'} = $error_message;
        return 0;
    }

    &Jarvis::Error::debug ($jconfig, 'Successful statement execution.  RetVal = ' . $stm->{'retval'});
    return 1;
}

################################################################################
# Gets our POSTDATA from a number of potential difference sources.  Stores it
# in $jconfig, just in case it is needed later.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               format              Either "json" or "xml" or "csv".
#
#       $rest_args_aref - Optional ref to our REST args (slash-separated after dataset).
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub get_post_data {
    my ($jconfig) = @_;

    $jconfig->{'post_data'} && return $jconfig->{'post_data'};

    # Get our submitted content.  This works for POST (insert) on non-XML data.  If the
    # content_type was "application/xml" then I think we will find our content in the
    # 'XForms:Model' parameter instead.
    $jconfig->{'post_data'} = $jconfig->{'cgi'}->param ('POSTDATA');

    # This is for POST (insert) on XML data.
    if (! $jconfig->{'post_data'}) {
        $jconfig->{'post_data'} = $jconfig->{'cgi'}->param ('XForms:Model');
    }

    # This works for DELETE (delete) and PUT (update) on any content.
    if (! $jconfig->{'post_data'}) {
        while (<STDIN>) {
            $jconfig->{'post_data'} .= $_;
        }
    }
    return $jconfig->{'post_data'};
}

################################################################################
# Loads the data for the current data set, and puts it into our return data
# hash so that it can be presented to the client in JSON.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               format              Either "json" or "xml" or "csv".
#
#       $rest_args_aref - Optional ref to our REST args (slash-separated after dataset).
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub fetch {
    my ($jconfig, $rest_args_aref) = @_;

    my $dsxml = &get_config_xml ($jconfig) || die "Cannot load configuration for dataset '" . ($jconfig->{'dataset_name'} || '') . "'.";

    my $allowed_groups = $dsxml->{dataset}{"read"};

    # Die on failure.  Note the trailing \n which blocks the stack-trace.
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{'status'} = "401 Unauthorized";
        die "Insufficient privileges to read '" . $jconfig->{'dataset_name'} . "'. $failure\n";
    }

    # What transformations should we use when sending out fetch data?
    my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->{dataset}{transform}{fetch});
    &Jarvis::Error::debug ($jconfig, "Fetch transformations = " . join (', ', keys %transforms) . " (applied to returned results)");

    # Attach to the database.
    my $dbh = &Jarvis::DB::handle ($jconfig);

    # Get our STM.  This has everything attached.
    my $stm = &parse_statement ($jconfig, $dsxml, $dbh, 'select') ||
        die "Dataset '" . ($jconfig->{'dataset_name'} || '') . "' has no SQL of type 'select'.";

    # Handle our parameters.  Always with placeholders.  Note that our special variables
    # like __username are safe, and cannot come from user-defined values.
    #
    my %raw_params = $jconfig->{'cgi'}->Vars;
    my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%raw_params, $rest_args_aref);

    # Store the params for logging purposes.
    my %params_copy = %safe_params;
    $jconfig->{'params_href'} = \%params_copy;

    # Convert the parameter names to corresponding values.
    my @arg_values = &names_to_values ($jconfig, $stm->{'vnames_aref'}, \%safe_params);

    # Execute Select, return on error
    &statement_execute($jconfig, $stm, \@arg_values);

    # On error, log and track the error, then return it to be given back as plain
    # text to the caller.  We don't wrap it in JSON or XML, since we don't want it
    # to be interpreted as "valid" data at all.
    #
    if ($stm->{'error'}) {
        $stm->{'sth'}->finish;
        &Jarvis::Tracker::error ($jconfig, '200', $stm->{'error'});
        return $stm->{'error'};
    }

    # Fetch the data.
    my $rows_aref = $stm->{'sth'}->fetchall_arrayref({});
    my $num_rows = scalar @$rows_aref;
    &Jarvis::Error::debug ($jconfig, "Number of rows fetched = $num_rows.");

    $stm->{'sth'}->finish;

    # Do we want to do server side sorting?  This happens BEFORE paging.  Note that this
    # will only work when $sth->{NAME} is available.  Some (all?) stored procedures
    # under MS-SQL Server will not provide field names, and hence this feature will not
    # be available.
    #
    my $sort_field = $jconfig->{'cgi'}->param ($jconfig->{'sort_field_param'}) || '';
    my $sort_dir = $jconfig->{'cgi'}->param ($jconfig->{'sort_dir_param'}) || 'ASC';

    if ($sort_field) {
        &Jarvis::Error::debug ($jconfig, "Server Sort on '$sort_field', Dir = '$sort_dir'.");
        my $field_names_aref = $stm->{'sth'}->{NAME};

        if (! grep { /$sort_field/ } @$field_names_aref) {
            &Jarvis::Error::log ($jconfig, "Unknown sort field: '$sort_field'.");

        } elsif (uc (substr ($sort_dir, 0, 1)) eq 'D') {
            @$rows_aref = sort { ($b->{$sort_field} || chr(255)) cmp ($a->{$sort_field} || chr(255)) } @$rows_aref;

        } else {
            @$rows_aref = sort { ($a->{$sort_field} || chr(255)) cmp ($b->{$sort_field} || chr(255)) } @$rows_aref;
        }
    }

    # Should we truncate the data to a specific page?
    my $limit = $jconfig->{'cgi'}->param ($jconfig->{'page_limit_param'}) || 0;
    my $start = $jconfig->{'cgi'}->param ($jconfig->{'page_start_param'}) || 0;

    if ($limit > 0) {
        ($start > 0) || ($start = 0); # Check we have a real zero, not ''

        &Jarvis::Error::debug ($jconfig, "Limit = $limit, Offset = $start, Num Rows = $num_rows.");

        if ($start > $#$rows_aref) {
            &Jarvis::Error::debug ($jconfig, "Page start over-run.  No data fetched perhaps.");
            @$rows_aref = ();

        } else {
            if (($start + ($limit - 1)) > $#$rows_aref) {
                &Jarvis::Error::debug ($jconfig, "Page finish over-run.  Partial page.");
                $limit = 1 + ($#$rows_aref - $start);
            }
            @$rows_aref = @$rows_aref[$start .. $start + ($limit - 1)];
        }
    }

    # Store the number of returned rows.
    $jconfig->{'out_nrows'} = scalar @$rows_aref;

    # Apply any output transformations to remaining hashes.
    if (scalar (keys %transforms)) {
        foreach my $row_href (@$rows_aref) {
            &transform (\%transforms, $row_href);
        }
    }

    # Delete null (undef) values, otherwise JSON/XML will represent them as ''.
    #
    # Note that this must happen AFTER the transform step, for two reasons:
    # (a) any preceding "notnull" transform (if specified for "fetch" on
    #     this dataset) will have turned NULLs into "" by this stage, meaning that
    #     we won't be deleting them here.
    #
    # (b) any preceding "null" transform will have set whitespace values to
    #     undef, meaning that we will now delete them here.
    #
    foreach my $row_href (@$rows_aref) {
        foreach my $key (keys %$row_href) {
            (defined $$row_href{$key}) || delete $$row_href{$key};
        }
    }

    # Return content in requested format.  JSON is simple.
    if ($jconfig->{'format'} eq "json") {
        my %return_data = ();

        $return_data {"logged_in"} = $jconfig->{'logged_in'};
        $return_data {"username"} = $jconfig->{'username'};
        $return_data {"error_string"} = $jconfig->{'error_string'};
        $return_data {"group_list"} = $jconfig->{'group_list'};

        # Note that we always return a "data" field, even if it is an empty array.
        # That is because ExtJS and other libraries will flag an exception if we do not.
        $return_data {"fetched"} = $num_rows;
        $return_data {"data"} = $rows_aref;

        my $json = JSON::PP->new->pretty(1);
        my $json_string = $json->encode ( \%return_data );
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($json_string));
        &Jarvis::Error::dump ($jconfig, $json_string);
        return $json_string;

    # XML is also simple.
    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();

        $xml->{'response'}{'logged_in'} = $jconfig->{'logged_in'};
        $xml->{'response'}{'username'} = $jconfig->{'username'};
        $xml->{'response'}{'error_string'} = $jconfig->{'error_string'};
        $xml->{'response'}{'group_list'} = $jconfig->{'group_list'};

        $xml->{'response'}{'fetched'} = $num_rows;
        if (scalar @$rows_aref) {
            $xml->{'response'}{'data'}{'row'} = $rows_aref;
        }

        my $xml_string = $xml->data ();
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($xml_string));
        &Jarvis::Error::dump ($jconfig, $xml_string);
        return $xml_string;

    # CSV format is the trickiest.  Note that it is dependent on the $sth->{NAME} data
    # being available.  In some cases, e.g. some (all?) stored procedures under MS-SQL
    # Server (definitely those using a pivot, and possibly others) the list of field
    # names is not available by this method, and hence this CSV cannot find the data
    # it requires.  In that case, you will need to write a "smart" plugin which can
    # figure out the field names itself, access the data with "rows_aref" format, and
    # put two and two together.
    #
    } elsif ($jconfig->{'format'} eq "csv") {

        my @field_names = @{ $stm->{'sth'}->{NAME} };
        my %field_index = ();

        @field_index { @field_names } = (0 .. $#field_names);

        # Create a string IO handle to print CSV into.
        my $output = '';
        my $io = IO::String->new ($output);

        # Create a CSV object and print the header line.
        my $csv = Text::CSV->new ();
        $csv->print ($io, \@field_names);
        print $io "\n";

        # Now print the data.
        foreach my $row_href (@$rows_aref) {
            my @columns = map { $$row_href{$_} } @field_names;
            $csv->print ($io, \@columns);
            print $io "\n";
        }

        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($output));
        &Jarvis::Error::dump ($jconfig, $output);
        return $output;

    # This is for INTERNAL use only!  Plugins for example might like to get the raw hash
    # and do their own formatting.  If you try this from a browser, you're going to
    # get something nasty happening.
    #
    } elsif ($jconfig->{'format'} eq "rows_aref") {
        return $rows_aref;

    } else {
        die "Unsupported format '" . $jconfig->{'format'} ."' for Dataset::fetch return data.\n";
    }
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
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub store {
    my ($jconfig, $rest_args_aref) = @_;

    my $dsxml = &get_config_xml ($jconfig) || die "Cannot load configuration for dataset '" . ($jconfig->{'dataset_name'} || '') . "'.";

    my $allowed_groups = $dsxml->{dataset}{"write"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{'status'} = "401 Unauthorized";
        die "Insufficient privileges to write '" . $jconfig->{'dataset_name'} . "'. $failure\n";
    }

    # What transforms should we use when processing store data?
    my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->{dataset}{transform}{store});
    &Jarvis::Error::debug ($jconfig, "Store transformations = " . join (', ', keys %transforms) . " (applied to incoming row data)");

    # Get our submitted content
    my $content = &get_post_data ($jconfig);
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
    my $dbh = &Jarvis::DB::handle ($jconfig);
    $dbh->begin_work() || die;

    # Loop for each set of updates.
    my $success = 1;
    my $modified = 0;
    my @results = ();
    my $message = '';

    # We pre-compute the "before" statement parameters even if there is no before statement,
    # since we may also wish to log them.  It's not
    my %restful_params = &Jarvis::Config::safe_variables ($jconfig, {}, $rest_args_aref);
    my %params_copy = %restful_params;
    $jconfig->{'params_href'} = \%params_copy;

    # Execute our "before" statement.  This statement is NOT permitted to fail.  If it does,
    # then we immediately barf
    {
        my $bstm = &parse_statement ($jconfig, $dsxml, $dbh, 'before');
        if ($bstm) {
            my @barg_values = &names_to_values ($jconfig, $bstm->{'vnames_aref'}, \%restful_params);

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
            &transform (\%transforms, \%safe_params);
        }

        # Figure out which statement type we will use for this row.
        my $row_ttype = $safe_params{'_ttype'} || $ttype;
        ($row_ttype eq 'mixed') && die "Transaction Type 'mixed', but no '_ttype' field present in row.";

        # Get the statement type for this ttype if we don't have it.  This raises debug.
        if (! $stm{$row_ttype}) {
            $stm{$row_ttype} = &parse_statement ($jconfig, $dsxml, $dbh, $row_ttype);
        }

        # Check we have an stm for this row.
        my $stm = $stm{$row_ttype} ||
            die "Dataset '" . ($jconfig->{'dataset_name'} || '') . "' has no SQL of type '$row_ttype'.";

        # Determine our argument values.
        my @arg_values = &names_to_values ($jconfig, $stm->{'vnames_aref'}, \%safe_params);

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
            &Jarvis::Tracker::error ($jconfig, '200', $stm->{'error'});

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

                        &Jarvis::Error::log ($jconfig, "Failure fetching first return result set for '" . $stm->{'ttype'} . "'.  Details follow.");
                        &Jarvis::Error::log ($jconfig, $stm->{'sql_with_placeholders'}) if $stm->{'sql_with_placeholders'};
                        &Jarvis::Error::log ($jconfig, $error_message);
                        &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) || 'NONE'));

                        $stm->{'sth'}->finish;
                        $stm->{'error'} = $error_message;
                        $success = 0;
                        $message = $error_message;
                    }

                    $row_result{'returning'} = $returning_aref;
                    $jconfig->{'out_nrows'} = scalar @$returning_aref;
                    &Jarvis::Error::debug ($jconfig, "Fetched " . (scalar @$returning_aref) . " rows for returning.");


                # Hmm... we're supposed to be returning data, but the query didn't give
                # us any.  Interesting.  Maybe it's SQLite?  In that case, we need to
                # go digging for the return values via last_insert_rowid().
                #
                } elsif ($row_ttype eq 'insert') {
                    my $rowid = $dbh->func('last_insert_rowid');
                    if ($rowid) {
                        my %return_values = %safe_params;
                        $return_values {'id'} = $rowid;

                        $row_result{'returning'} = [ \%return_values ];
                        $jconfig->{'out_nrows'} = 1;
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

                        &Jarvis::Error::log ($jconfig, "Failure fetching additional result sets for '" . $stm->{'ttype'} . "'.  Details follow.");
                        &Jarvis::Error::log ($jconfig, $stm->{'sql_with_placeholders'}) if $stm->{'sql_with_placeholders'};
                        &Jarvis::Error::log ($jconfig, $error_message);
                        &Jarvis::Error::log ($jconfig, "Args = " . (join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) || 'NONE'));

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
        my $astm = &parse_statement ($jconfig, $dsxml, $dbh, 'after');
        if ($astm) {
            my @aarg_values = &names_to_values ($jconfig, $astm->{'vnames_aref'}, \%restful_params);

            &statement_execute($jconfig, $astm, \@aarg_values);
            if ($astm->{'error'}) {
                $success = 0;
                $message || ($message = $astm->{'error'});
            }
        }
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

    # Note here that our return structure is different depending on whether you handed us
    # just one record (not in an array), or if you gave us an array of records.  An array
    # containing one record is NOT the same as a single record not in an array.
    #
    if ($jconfig->{'format'} eq "json") {
        my %return_data = ();
        $return_data {'success'} = $success;
        $success && ($return_data {'modified'} = $modified);
        $success || ($return_data {'message'} = &trim($message));

        # Return the array data if we succeded.
        if ($success && $return_array) {
            $return_data {'row'} = \@results;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $results[0]{'returning'} && ($return_data {'returning'} = $results[0]{'returning'});
        }
        my $json = JSON::PP->new->pretty(1);
        my $json_string = $json->encode ( \%return_data );
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($json_string));
        &Jarvis::Error::dump ($jconfig, $json_string);
        return $json_string;

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{'response'}{'success'} = $success;
        $success && ($xml->{'response'}{'modified'} = $modified);
        $success || ($xml->{'response'}{'message'} = &trim($message));

        # Return the array data if we succeeded.
        if ($success && $return_array) {
            $xml->{'response'}{'results'}->{'row'} = \@results;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $results[0]{'returning'} && ($xml->{'response'}{'returning'} = $results[0]{'returning'});
        }
        my $xml_string = $xml->data ();
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($xml_string));
        &Jarvis::Error::dump ($jconfig, $xml_string);
        return $xml_string;

    } else {
        die "Unsupported format '" . $jconfig->{'format'} ."' for Dataset::store return data.\n";
    }
}

1;
