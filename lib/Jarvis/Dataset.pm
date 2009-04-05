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

package Jarvis::Dataset;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;

my %yes_value = ('yes' => 1, 'true' => 1, '1' => 1);

###############################################################################
# Internal Functions
###############################################################################

################################################################################
# Loads the DataSet config from the config dir and returns it as XML.
#
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Find our user-supplied "dataset" name.
#               xml                 Find our app-configured "dataset_dir" dir.
#           WRITE
#               dataset_name        Stored for the benefit of error/debug.
#               use_placeholders    Should we use placeholders?  Or just insert text?
#               max_rows            Passed through as {{__max_rows}} to SQL.
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
        &Jarvis::Error::my_die ($jconfig,  "No attribute 'dataset_dir' configured.");
    &Jarvis::Error::debug ($jconfig, "Dataset Directory '$dataset_dir'.");

    # Now we require 'dataset' to also be a CGI parameter.  We store this in the
    # $jconfig 
    my $dataset_name = $cgi->param ('dataset') || die "Missing mandatory parameter 'dataset'!\n";
    ($dataset_name =~ m/^\w+$/) || die "Invalid characters in parameter 'dataset'\n";
    $jconfig->{'dataset_name'} = $dataset_name;
    &Jarvis::Error::debug ($jconfig, "Dataset Directory '$dataset_dir'.");

    # Load the dataset-specific XML file and double-check it has top-level <dataset> tag.
    my $dsxml_filename = "$dataset_dir/$dataset_name.xml";
    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # Load a couple of other parameters.  This is a "side-effect".  Yeah, it's a bit yucky.
    $jconfig->{'use_placeholders'} = defined ($Jarvis::Config::yes_value {lc ($axml->{'use_placeholders'}->content || "no")});
    $jconfig->{'max_rows'} = lc ($axml->{'max_rows'}->content || 200);

    return $dsxml;
}

################################################################################
# Get the SQL for the update, insert, and delete.
#
# Params:
#       $jconfig - Jarvis::Config object (used for my_die)
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
    $sql || &Jarvis::Error::my_die ($jconfig, "This dataset has no SQL of type '$which'.");
    $sql = &trim ($sql);

    return $sql;
}

################################################################################
# Adds some special variables to our name -> value map.  Note that our special
# variables are added AFTER the user-provided variables.  That means that you
# can securely rely upon the values of __username, __grouplist, etc.  If the
# caller attempts to supply them, ours will replace the hacked values.
#
#   __username  -> <logged-in-username>
#   __grouplist -> ('<group1>', '<group2>', ...)
#   __group:<groupname>  ->  1 (iff belong to <groupname>) or NULL
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               username
#               group_list
#               max_rows
#
#       Hash of Args (* indicates mandatory)
#               username, group_list
#
# Returns:
#       1
################################################################################
#
sub add_special_dataset_variables {

    my ($jconfig, $param_values_href) = @_;

    # These are '' if we have not logged in, but must ALWAYS be defined.  In
    # theory, any datasets which allows non-logged-in access is not going to
    # reference __username
    #
    $$param_values_href{"__username"} = $jconfig->{'username'};
    $$param_values_href{"__grouplist"} = "('" . join ("','", split (',', $jconfig->{'group_list'})) . "')";
    foreach my $group (split (',', $jconfig->{'group_list'})) {
        $$param_values_href{"__group:$group"} = 1;
    }

    # These can be passed by the client, we just set defaults if needed.
    $$param_values_href{"__max_rows"} || ($$param_values_href{"__max_rows"} = $jconfig->{'max_rows'});
    $$param_values_href{"__first_row"} || ($$param_values_href{"__first_row"} = 1);

    return 1;
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
#       Param Values hash
#
# Returns:
#       ($sql_with_variables).
#       die on error.
################################################################################
#
sub sql_with_variables {

    my ($sql, %param_values) = @_;

    # Parse the update SQL to get a prepared statement, pulling out the list
    # of names of variables we need to replace for each execution.
    my $sql_with_variables = "";
    my @bits = split (/\{\{?\$?([^\}]+)\}\}?/i, $sql);

    my $num_params = 0;
    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $variable_name = $bits[$idx];
            my $variable_value = $param_values{$variable_name};
            if (! defined $variable_value) {
                $variable_value = 'NULL';

            } elsif ($variable_value =~ m/^\-?[0-9]+(\.[0-9]+)?$/) {
                # Numeric, do not quote.

            } elsif ($variable_name eq "__grouplist") {
                # Array, do not quote.

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
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub fetch {
    my ($jconfig) = @_;

    my $dsxml = &get_config_xml ($jconfig) || die "Cannot load configuration for dataset.\n";

    my $allowed_groups = $dsxml->{dataset}{"read"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    $failure && &Jarvis::Error::my_die ($jconfig, "Wanted read access: $failure");

    my $sql = &get_sql ($jconfig, 'select', $dsxml);

    # Handle our parameters.  Either inline or with placeholders.  Note that our
    # special variables like __username will override sneaky user-supplied values.
    #
    my %param_values = $jconfig->{'cgi'}->Vars;
    &add_special_dataset_variables ($jconfig, \%param_values);

    my @arg_values = ();
    if ($jconfig->{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &sql_with_placeholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = map { $param_values{$_} } @variable_names;

    } else {
        my $sql_with_variables = &sql_with_variables ($sql, %param_values);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::debug ($jconfig, "FETCH = " . $sql);

    my $dbh = &Jarvis::DB::Handle ($jconfig);
    my $sth = $dbh->prepare ($sql)
        || &Jarvis::Error::my_die ($jconfig, "Couldn't prepare statement '$sql': " . $dbh->errstr);

    # Execute
    my $num_rows = 0;
    my $err_handler = $SIG{__DIE__};
    eval {
        $SIG{__DIE__} = sub {};
        $num_rows = $sth->execute (@arg_values);
    };
    $SIG{__DIE__} = $err_handler;

    if ($@) {
        print STDERR "ERROR: Couldn't execute select '$sql' with args '" . join ("','", map { $_ || 'NULL' } @arg_values) . "'\n";
        print STDERR $sth->errstr . "!\n";
        my $message = $sth->errstr;
        $sth->finish;
        return $message;
    }

    my $rows_aref = $sth->fetchall_arrayref({});
    $sth->finish;

    # Return content in requested format.
    if ($jconfig->{'format'} eq "json") {
        my %return_data = ();
        $return_data {"fetched"} = $num_rows;
        $return_data {"data"} = $rows_aref;

        my $json = JSON::XS->new->pretty(1);
        return $json->encode ( \%return_data );

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{fetched} = $num_rows;
        $xml->{data}{row} = $rows_aref;

        return $xml->data ();

    } elsif ($jconfig->{'format'} eq "csv") {
        my @field_names = @{ $sth->{NAME} };
        my %field_index = ();

        @field_index { @field_names } = (0 .. $#field_names);

        foreach my $i (0 .. $#field_names) {
            print STDERR "$i: $field_names[$i]\n";
        }
        my $csv = Text::CSV->new();
        $csv->print (*STDOUT, \@field_names);

    } else {
        &Jarvis::Error::my_die ($jconfig, "Unsupported format '" . $jconfig->{'format'} ."' for Dataset::fetch return data.\n");
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
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub store {
    my ($jconfig) = @_;

    my $dsxml = &get_config_xml ($jconfig) || die "Cannot load configuration for dataset.\n";

    my $allowed_groups = $dsxml->{dataset}{"write"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    $failure && &Jarvis::Error::my_die ($jconfig, "Wanted write access: $failure");

    # Check we have some changes and parse 'em from the JSON.  We get an
    # array of hashes.  Each array entry is a change record.
    my $changes_json = $jconfig->{'cgi'}->param ('fields')
         || die &Jarvis::Error::my_die($jconfig, "Missing mandatory store parameter 'fields'.");

    my $fields_href = JSON::XS->new->utf8->decode ($changes_json);

    # Choose our statement and find the SQL and variable names.
    my $transaction_type = $$fields_href{'_transaction_type'};
    my $sql = undef;
    my @variable_names = undef;

    # Does this insert return rows?
    my $returning = 0;

    # DELETE
    if ($transaction_type eq "delete") {
        $sql = &get_sql ($jconfig, 'delete', $dsxml);

    # UPDATE
    } elsif ($transaction_type eq "update") {
        $sql = &get_sql ($jconfig, 'update', $dsxml);

    # INSERT, possibly returning.
    } elsif ($transaction_type eq "insert") {
        $sql = &get_sql ($jconfig, 'insert', $dsxml);
        $returning = defined ($yes_value {lc ($dsxml->{dataset}{'insert'}{'returning'} || "no")});
        &Jarvis::Error::debug ($jconfig, "Insert Returning = " . $returning);

    } else {
        &Jarvis::Error::my_die ($jconfig, "Unsupported transaction type '$transaction_type'.");
    }

    # Handle our parameters.  Either inline or with placeholders.  Note that our
    # special variables like __username will override sneaky user-supplied values.
    #
    my %param_values = %{ $fields_href };
    &add_special_dataset_variables ($jconfig, \%param_values);

    my @arg_values = ();
    if ($jconfig->{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &sql_with_placeholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = map { $param_values{$_} } @variable_names;
        &Jarvis::Error::debug ($jconfig, "Statement Args = " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values));

    } else {
        my $sql_with_variables = &sql_with_variables ($sql, %param_values);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::debug ($jconfig, "STORE = " . $sql);

    my $dbh = &Jarvis::DB::Handle ($jconfig);
    my $sth = $dbh->prepare ($sql)
        || &Jarvis::Error::my_die ($jconfig, "Couldn't prepare statement '$sql': " . $dbh->errstr);

    # Execute
    my $num_rows = 0;
    my $err_handler = $SIG{__DIE__};
    eval {
        $SIG{__DIE__} = sub {};
        $num_rows = $sth->execute (@arg_values);
    };
    $SIG{__DIE__} = $err_handler;

    if ($@) {
        print STDERR "ERROR: Couldn't execute $transaction_type '$sql' with args '" . join ("','", map { $_ || 'NULL' } @arg_values) . "'\n";
        print STDERR $sth->errstr . "!\n";
        my $message = $sth->errstr;
        $sth->finish;

        if ($jconfig->{'format'} eq "json") {
            return "{ \"success\": 0, \"message\": \"" . &escape_java_script (&trim($message)) . "\"}";

        } elsif ($jconfig->{'format'} eq "xml") {
            my $xml = XML::Smart->new ();
            $xml->{success} = 0;
            $xml->{message} = &trim($message);
            return $xml->data ();

        } else {
            &Jarvis::Error::my_die ($jconfig, "Unsupported format '" . $jconfig->{'format'} ."' in Dataset::store error.\n");
        }
    }

    # Fetch the results, if this INSERT indicates that it returns values.
    my $rows_aref = $returning ? $sth->fetchall_arrayref({}) : undef;
    $sth->finish;

    # Return content in requested format.
    if ($jconfig->{'format'} eq "json") {
        my %return_data = ();
        $return_data {"success"} = 1;
        $return_data {"updated"} = $num_rows;
        $returning && ($return_data {"data"} = $rows_aref);

        my $json = JSON::XS->new->pretty(1);
        return $json->encode ( \%return_data );

    } elsif ($jconfig->{'format'} eq "xml") {
        my $xml = XML::Smart->new ();
        $xml->{success} = 1;
        $xml->{updated} = $num_rows;
        $returning && ($xml->{data}{row} = $rows_aref);

        return $xml->data ();

    } else {
        &Jarvis::Error::my_die ($jconfig, "Unsupported format '" . $jconfig->{'format'} ."' for Dataset::store return data.\n");
    }
}

1;
