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
use JSON::XS;
use XML::Smart;
use Text::CSV;
use IO::String;

package Jarvis::Dataset;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;

use sort 'stable';      # Don't mix up records when server-side sorting

my %yes_value = ('yes' => 1, 'true' => 1, '1' => 1);

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
#               use_placeholders    Should we use placeholders?  Or just insert text?
#               page_start_param    Name of the CGI param specifying page start row num
#               page_limit_param    Name of the CGI param specifying page limit row num
#               sort_field_param    Name of the CGI param specifying page sort field
#               sort_dir_param      Name of the CGI param specifying page sort direction
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

    # Now we require 'dataset' to also be a CGI parameter.  We store this in the
    # $jconfig
    my $dataset_name = $jconfig->{'dataset_name'};
    &Jarvis::Error::debug ($jconfig, "Dataset Name '$dataset_name'.");

    # Load the dataset-specific XML file and double-check it has top-level <dataset> tag.
    my $dsxml_filename = "$dataset_dir/$dataset_name.xml";
    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # Load a couple of other parameters.  This is a "side-effect".  Yeah, it's a bit yucky.
    $jconfig->{'use_placeholders'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'use_placeholders'}->content || "yes")});
    $jconfig->{'page_start_param'} = lc ($axml->{'page_start_param'}->content || 'page_start');
    $jconfig->{'page_limit_param'} = lc ($axml->{'page_limit_param'}->content || 'page_limit');
    $jconfig->{'sort_field_param'} = lc ($axml->{'sort_field_param'}->content || 'sort_field');
    $jconfig->{'sort_dir_param'} = lc ($axml->{'sort_dir_param'}->content || 'sort_dir');

    $jconfig->{'stop_on_error'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'stop_on_error'}->content || "yes")});
    $jconfig->{'rollback_on_error'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'rollback_on_error'}->content || "yes")});

    return $dsxml;
}

################################################################################
# Get the SQL for the update, insert, and delete.
#
# Params:
#       $jconfig - Jarvis::Config object (NOT USED YET)
#       $which   - SQL Type ("fetch", "insert", "update", "delete")
#       $dsxml   - XML::Smart object for dataset configuration
#
# Returns:
#       ($sql, @variable_names).
#       die on error.
################################################################################
#
sub get_sql {
    my ($jconfig, $which, $dsxml) = @_;

    my $sql = $dsxml->{dataset}{$which}->content;
    $sql || die "Dataset '" . ($jconfig->{'dataset_name'} || '') . "' has no SQL of type '$which'.";
    $sql =~ s/^\s*\-\-.*$//gm;   # Remove SQL comments
    $sql = &trim ($sql);

    return $sql;
}

################################################################################
# Expand the SQL, replace args with ?, and return list of arg names.
#
# Params:
#       SQL text.
#
# Returns:
#       ($sql_with_placeholders, @variable_names).
#       die on error.
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
# Expand the SQL, replace args with ?, and return list of arg names.
#
# Params:
#       SQL text.
#       Safe Param Values hash
#
# Returns:
#       ($sql_with_variables).
#       die on error.
################################################################################
#
sub sql_with_variables {

    my ($sql, %safe_params) = @_;

    # Parse the update SQL to get a prepared statement, pulling out the list
    # of names of variables we need to replace for each execution.
    my $sql_with_variables = "";
    my @bits = split (/\{\{?\$?([^\}]+)\}\}?/i, $sql);

    my $num_params = 0;
    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $variable_name = $bits[$idx];
            my $variable_value = undef;
            foreach my $option (split ('\|', $variable_name)) {
                $variable_value = $safe_params {$option};
                last if (defined $variable_value);
            }

            if (! defined $variable_value) {
                $variable_value = 'NULL';

            } elsif ($variable_value =~ m/^\-?[0-9]+(\.[0-9]+)?$/) {
                # Numeric, do not quote.

            } else {
                $variable_value =~ s/'/''/;
                $variable_value = "'" . $variable_value . "'";
            }

            $sql_with_variables .= $variable_value;

        } else {
            $sql_with_variables .= $bits[$idx];
        }
    }

    return $sql_with_variables;
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
    my ($variable_names_aref, $safe_params_href) = @_;

    my @arg_values = ();
    foreach my $name (@$variable_names_aref) {
        my $value = undef;
        foreach my $option (split ('\|', $name)) {
            $value = $$safe_params_href {$option};
            last if (defined $value);
        }
        push (@arg_values, $value);
    }
    return @arg_values;
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
#               with_placeholders   Should we use placeholders or string subst in SQL
#               format              Either "json" or "xml" or "csv".
#
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub fetch {
    my ($jconfig, $rest_args_aref) = @_;

    my $dsxml = &get_config_xml ($jconfig) || die "Cannot load configuration for dataset '" . ($jconfig->{'dataset_name'} || '') . "'.\n";

    my $allowed_groups = $dsxml->{dataset}{"read"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    $failure && die "Wanted read access: $failure\n";

    my $sql = &get_sql ($jconfig, 'select', $dsxml);

    # Handle our parameters.  Either inline or with placeholders.  Note that our
    # special variables like __username are safe, and cannot come from user-defined
    # values.
    #
    my %raw_params = $jconfig->{'cgi'}->Vars;
    my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%raw_params, $rest_args_aref);

    my @arg_values = ();
    if ($jconfig->{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &sql_with_placeholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = &names_to_values (\@variable_names, \%safe_params);

    } else {
        my $sql_with_variables = &sql_with_variables ($sql, %safe_params);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::debug ($jconfig, "FETCH = " . $sql);
    &Jarvis::Error::debug ($jconfig, "ARGS = " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values));

    my $dbh = &Jarvis::DB::Handle ($jconfig);
    my $sth = $dbh->prepare ($sql)
        || die "Couldn't prepare statement '$sql': " . $dbh->errstr;

    # Execute
    my $status = 0;
    my $err_handler = $SIG{__DIE__};
    eval {
        $SIG{__DIE__} = sub {};
        $status = $sth->execute (@arg_values);
    };
    $SIG{__DIE__} = $err_handler;

    if ($@) {
        print STDERR "ERROR: Couldn't execute select '$sql' with args " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) . "\n";
        print STDERR $sth->errstr . "!\n";
        my $message = $sth->errstr;
        $sth->finish;
        return $message;
    }

    my $rows_aref = $sth->fetchall_arrayref({});
    my $num_rows = scalar @$rows_aref;
    $sth->finish;

    # Do we want to do server side sorting?  This happens BEFORE paging.
    #
    my $sort_field = $jconfig->{'cgi'}->param ($jconfig->{'sort_field_param'}) || '';
    my $sort_dir = $jconfig->{'cgi'}->param ($jconfig->{'sort_dir_param'}) || 'ASC';

    if ($sort_field) {
        &Jarvis::Error::debug ($jconfig, "Server Sort on '$sort_field', Dir = '$sort_dir'.");
        my $field_names_aref = $sth->{NAME};

        if (! grep { /$sort_field/ } @$field_names_aref) {
            &Jarvis::Error::log ($jconfig, "Unknown sort field: '$sort_field'.");

        } elsif (uc (substr ($sort_dir, 0, 1)) eq 'D') {
            @$rows_aref = sort { ($b->{$sort_field} || chr(255)) cmp ($a->{$sort_field} || chr(255)) } @$rows_aref;

        } else {
            @$rows_aref = sort { ($a->{$sort_field} || chr(255)) cmp ($b->{$sort_field} || chr(255)) } @$rows_aref;
        }
    }

    # Should we truncate the data to a specific page?
    #
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

    # Return content in requested format.  JSON is simple.
    if ($jconfig->{'format'} eq "json") {
        my %return_data = ();

        $return_data {"logged_in"} = $jconfig->{'logged_in'};
        $return_data {"username"} = $jconfig->{'username'};
        $return_data {"error_string"} = $jconfig->{'error_string'};
        $return_data {"group_list"} = $jconfig->{'group_list'};

        $return_data {"fetched"} = $num_rows;
        $return_data {"data"} = $rows_aref;

        my $json = JSON::XS->new->pretty(1);
        return $json->encode ( \%return_data );

    # XML is also simple.
    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();

        $xml->{logged_in} = $jconfig->{'logged_in'};
        $xml->{username} = $jconfig->{'username'};
        $xml->{error_string} = $jconfig->{'error_string'};
        $xml->{group_list} = $jconfig->{'group_list'};

        $xml->{fetched} = $num_rows;
        $xml->{data}{row} = $rows_aref;

        return $xml->data ();

    # CSV format is the trickiest.
    } elsif ($jconfig->{'format'} eq "csv") {

        # Get the list of column names from our fetch statement.
        my @field_names = @{ $sth->{NAME} };
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

        return $output;

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
#               with_placeholders   Should we use placeholders or string subst in SQL
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

    my $dsxml = &get_config_xml ($jconfig) || die "Cannot load configuration for dataset.\n";

    my $allowed_groups = $dsxml->{dataset}{"write"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    $failure && die "Wanted write access: $failure";

    # Get our submitted content.  This works for POST (insert) on non-XML data.  If the
    # content_type was "application/xml" then I think we will find our content in the
    # 'XForms:Model' parameter instead.
    my $content = $jconfig->{'cgi'}->param ('POSTDATA');

    # This is for POST (insert) on XML data.
    if (! $content) {
        $content = $jconfig->{'cgi'}->param ('XForms:Model');
    }

    # This works for DELETE (delete) and PUT (update) on any content.
    if (! $content) {
        while (<STDIN>) {
            $content .= $_;
        }
    }
    $content || die "Cannot find client-submitted change content.";

    # Fields we need to store.  This is an ARRAY ref to multiple rows each a HASH REF
    my $fields_aref = undef;

    # Check we have some changes and parse 'em from the JSON.  We get an
    # array of hashes.  Each array entry is a change record.
    my $return_array = 0;
    my $content_type = $jconfig->{'cgi'}->content_type () || '';
    if ($content_type =~ m|^[a-z]+/json(; .*)?$|) {
        my $ref = JSON::XS->new->utf8->decode ($content);

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

        # Fields may either sit at the top level, or you may provide an array of
        # records in a <rows> array.
        #
        my @rows = ();
        if ($cxml->{'request'}{'rows'}) {
            foreach my $row (@{ $cxml->{'request'}{'rows'} }) {
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

    # Choose our statement and find the SQL and variable names.
    my $transaction_type = $jconfig->{'action'};
    my $base_sql = undef;

    # Does this insert return rows?
    my $returning = 0;

    # DELETE
    if ($transaction_type eq "delete") {
        $base_sql = &get_sql ($jconfig, 'delete', $dsxml);

    # UPDATE
    } elsif ($transaction_type eq "update") {
        $base_sql = &get_sql ($jconfig, 'update', $dsxml);

    # INSERT, possibly returning.
    } elsif ($transaction_type eq "insert") {
        $base_sql = &get_sql ($jconfig, 'insert', $dsxml);
        $returning = defined ($yes_value {lc ($dsxml->{dataset}{'insert'}{'returning'} || "no")});
        &Jarvis::Error::debug ($jconfig, "Insert Returning = " . $returning);

    } else {
        die "Unsupported transaction type '$transaction_type'.";
    }

    # For placeholders, we can do this once outside the update loop.  For textual
    # substitution it's far less efficient of course.
    #
    my $dbh = &Jarvis::DB::Handle ($jconfig);
    $dbh->begin_work() || die;

    my $sth = undef;
    my $sql = undef;
    my @variable_names = undef;                 # Used only for placeholder case.

    if ($jconfig->{'use_placeholders'}) {
        ($sql, @variable_names) = &sql_with_placeholders ($base_sql);

        &Jarvis::Error::debug ($jconfig, "STORE = " . $sql);
        $sth = $dbh->prepare ($sql) || die "Couldn't prepare statement '$sql': " . $dbh->errstr;
    }

    # Loop for each set of updates.
    my $success = 1;
    my $modified = 0;
    my @results = ();
    my $message = '';

    foreach my $fields_href (@$fields_aref) {
        my %row_result = ();

        # Handle our parameters.  Either inline or with placeholders.  Note that our
        # special variables like __username are safe, and cannot come from user-defined
        # values.
        #
        my %raw_params = %{ $fields_href };
        my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%raw_params, $rest_args_aref);

        my @arg_values = ();
        if ($jconfig->{'use_placeholders'}) {
            @arg_values = &names_to_values (\@variable_names, \%safe_params);
            &Jarvis::Error::debug ($jconfig, "ARGS = " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values));

        } else {
            $sql = &sql_with_variables ($base_sql, %safe_params);

            &Jarvis::Error::debug ($jconfig, "STORE = " . $sql);
            $sth = $dbh->prepare ($sql) || die "Couldn't prepare statement '$sql': " . $dbh->errstr;
        }

        # Prepare
        # Execute
        my $stop = 0;
        my $num_rows = 0;
        my $err_handler = $SIG{__DIE__};
        eval {
            $SIG{__DIE__} = sub {};
            $row_result{'modified'} = $sth->execute (@arg_values);
            $modified = $modified + $row_result{'modified'};
        };
        $SIG{__DIE__} = $err_handler;

        if ($@) {
            print STDERR "ERROR: Couldn't execute $transaction_type '$sql' with args " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values) . "\n";
            print STDERR $sth->errstr . "!\n";
            $row_result{'success'} = 0;
            $row_result{'message'} = $sth->errstr;
            $success = 0;
            $message || ($message = $sth->errstr);

            if ($jconfig->{'stop_on_error'}) {
                &Jarvis::Error::debug ($jconfig, "Error detected and 'stop_on_error' configured.");
                $stop = 1;
            }


        # Suceeded.  Set per-row status, and fetch the returned results, if this
        # operation indicates that it returns values.
        #
        } else {
            $row_result{'success'} = 1;

            if ($returning) {
                my $returning_aref = $sth->fetchall_arrayref({}) || undef;
                if ($returning_aref) {
                    $row_result{'returning'} = $returning_aref;
                }
            }

        }

        # Not using placeholders, free statement each loop.
        if (! $jconfig->{'use_placeholders'}) {
            $sth->finish;
        }
        push (@results, \%row_result);
        last if $stop;
    }

    # Using placeholders, free statement only at the end.
    if ($jconfig->{'use_placeholders'}) {
        $sth->finish;
    }

    my $state = undef;
    if ((! $success) && $jconfig->{'rollback_on_error'}) {
        &Jarvis::Error::debug ($jconfig, "Error detected and 'rollback_on_error' configured.");
        $dbh->rollback ();
        $state = 'rollback';

    } else {
        if ($success) {
            &Jarvis::Error::debug ($jconfig, "All successful.  Committing all changes.");

        } else {
            &Jarvis::Error::debug ($jconfig, "Some changes failed.  Committing anyhow.");
        }
        $dbh->commit ();
        $state = 'commit';
    }

    # Return content in requested format.
    &Jarvis::Error::debug ($jconfig, "Return Array = $return_array.");

    # Note here that our return structure is different depending on whether you handed us
    # just one record (not in an array), or if you gave us an array of records.  An array
    # containing one record is NOT the same as a single record not in an array.
    #
    if ($jconfig->{'format'} eq "json") {
        my %return_data = ();
        $return_data {'success'} = $success;
        $return_data {'state'} = $state;
        $return_data {'modified'} = $modified;
        $success || ($return_data {'message'} = &trim($message));

        # Always return the array data.
        if ($return_array) {
            $return_data {'rows'} = \@results;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $results[0]{'returning'} && ($return_data {'returning'} = $results[0]{'returning'});
        }
        my $json = JSON::XS->new->pretty(1);
        return $json->encode ( \%return_data );

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{'success'} = $success;
        $xml->{'state'} = $state;
        $xml->{'modified'} = $modified;
        $success || ($xml->{'message'} = &trim($message));

        # Always return the array data.
        if ($return_array) {
            $xml->{'results'}{'rows'} = \@results;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $results[0]{'returning'} && ($xml->{'returning'} = $results[0]{'returning'});
        }
        return $xml->data ();

    } else {
        die "Unsupported format '" . $jconfig->{'format'} ."' for Dataset::store return data.\n";
    }
}

1;
