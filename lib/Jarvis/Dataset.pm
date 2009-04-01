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
#               cgi                 Contains data values for {{param}} in SQL
#               dataset_dir         Where to look for our dataset XML files
#               dataset_name        Specifies our <dataset_name>.xml DS config file
#
# Returns:
#       $dsxml - XML::Smart object holding config info read from file.
################################################################################
#
sub GetConfigXML {
    my ($jconfig) = @_;

    my $cgi = $jconfig->{"cgi"};
    my $dataset_dir = $jconfig->{"dataset_dir"};

    # Now we require 'dataset' to also be a CGI parameter.
    my $dataset_name = $cgi->param ('dataset') || die "Missing mandatory parameter 'dataset'!\n";
    ($dataset_name =~ m/^\w+$/) || die "Invalid characters in parameter 'dataset'\n";
    $jconfig->{"dataset_name"} = $dataset_name;

    # Load the dataset-specific XML file.
    my $dsxml_filename = "$dataset_dir/$dataset_name.xml";
    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # Now we have dataset config.  Add to our list of args.
    return $dsxml;
}

################################################################################
# Get the SQL for the update, insert, and delete.
#
# Params:
#       $jconfig - Jarvis::Config object (used for MyDie)
#       $which   - SQL Type ("fetch", "insert", "update", "delete")
#       $dsxml   - XML::Smart object for dataset configuration
#
# Returns:
#       ($sql, @variable_names).
#       die on error.
################################################################################
#
sub GetSQL {
    my ($jconfig, $which, $dsxml) = @_;

    my $sql = $dsxml->{dataset}{$which}->content;
    $sql || &Jarvis::Error::MyDie ($jconfig, "This dataset has no SQL of type '$which'.");
    $sql = &Trim ($sql);

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
sub AddSpecialDatasetVariables {

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
sub SqlWithPlaceholders {

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
sub SqlWithVariables {

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
#               dataset_dir         Where to look for our dataset XML files
#               dataset_name        Specifies our <dataset_name>.xml DS config file
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               with_placeholders   Should we use placeholders or string subst in SQL
#               format              Either "json" or "xml".
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub Fetch {
    my ($jconfig) = @_;

    my $dsxml = &GetConfigXML ($jconfig) || die "Cannot load configuration for dataset.\n";

    my $allowed_groups = $dsxml->{dataset}{"read"};
    my $failure = &Jarvis::Login::CheckAccess ($jconfig, $allowed_groups);
    $failure && &Jarvis::Error::MyDie ($jconfig, "Wanted read access: $failure");

    my $sql = &GetSQL ($jconfig, 'select', $dsxml);

    # Handle our parameters.  Either inline or with placeholders.  Note that our
    # special variables like __username will override sneaky user-supplied values.
    #
    my %param_values = $jconfig->{'cgi'}->Vars;
    &AddSpecialDatasetVariables ($jconfig, \%param_values);

    my @arg_values = ();
    if ($jconfig->{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &SqlWithPlaceholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = map { $param_values{$_} } @variable_names;

    } else {
        my $sql_with_variables = &SqlWithVariables ($sql, %param_values);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::Debug ($jconfig, "FETCH = " . $sql);

    my $dbh = &Jarvis::DB::Handle ($jconfig);
    my $sth = $dbh->prepare ($sql)
        || &Jarvis::Error::MyDie ($jconfig, "Couldn't prepare statement '$sql': " . $dbh->errstr);

    # Execute
    my $num_rows = 0;
    eval {
        my $err_handler = $SIG{__DIE__};
        $SIG{__DIE__} = sub {};
        $num_rows = $sth->execute (@arg_values);
        $SIG{__DIE__} = $err_handler;
    };
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

    } else {
        my $xml = XML::Smart->new ();
        $xml->{fetched} = $num_rows;
        $xml->{data}{row} = $rows_aref;

        return $xml->data ();
    }
}

################################################################################
# Performs an update to the specified table underlying the named dataset.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               dataset_dir         Where to look for our dataset XML files
#               dataset_name        Specifies our <dataset_name>.xml DS config file
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               with_placeholders   Should we use placeholders or string subst in SQL
#               format              Either "json" or "xml".
#
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub Store {
    my ($jconfig) = @_;

    my $dsxml = &GetConfigXML ($jconfig) || die "Cannot load configuration for dataset.\n";

    my $allowed_groups = $dsxml->{dataset}{"write"};
    my $failure = &Jarvis::Login::CheckAccess ($jconfig, $allowed_groups);
    $failure && &Jarvis::Error::MyDie ($jconfig, "Wanted write access: $failure");

    # Figure out what field is our "serial" ID.  Normally it is "id", but it
    # could change.
    my $serial_name = $dsxml->{dataset}{serial};
    $serial_name || &Jarvis::Error::MyDie ($jconfig, "This dataset has no serial ID parameter.");

    # Check we have some changes and parse 'em from the JSON.  We get an
    # array of hashes.  Each array entry is a change record.
    my $changes_json = $jconfig->{'cgi'}->param ('fields')
         || die &Jarvis::Error::MyDie("Missing mandatory store parameter 'fields'.");

    my $fields_href = JSON::XS->new->utf8->decode ($changes_json);
    # Choose our statement and find the SQL and variable names.
    my $transaction_type = $$fields_href{'_transaction_type'};

    # Note: Serial value may be undefined, if we are creating a new record.
    my $serial_value = $$fields_href{$serial_name};
    my $sql = undef;
    my @variable_names = undef;

    # Does this insert return rows?
    my $returning = 0;

    # Remove => DELETE.  Must have a serial code present.
    if ($transaction_type eq "remove") {
        ((defined $serial_value) && ($serial_value ne ''))
            || &Jarvis::Error::MyDie ($jconfig, "Cannot delete entry with missing serial.");

        $sql = &GetSQL ($jconfig, 'delete', $dsxml);

    # Update => INSERT or UPDATE.
    } elsif ($transaction_type eq "update") {
        if ((defined $serial_value) && ($serial_value > 0)) {
            $sql = &GetSQL ($jconfig, 'update', $dsxml);

        } else {
            $sql = &GetSQL ($jconfig, 'insert', $dsxml);
            $returning = defined ($yes_value {lc ($dsxml->{dataset}{'insert'}{'returning'} || "no")});
            &Jarvis::Error::Debug ($jconfig, "Insert Returning = " . $returning);
        }

    } else {
        &Jarvis::Error::MyDie ($jconfig, "Unsupported transaction type '$transaction_type'.");
    }

    # Handle our parameters.  Either inline or with placeholders.  Note that our
    # special variables like __username will override sneaky user-supplied values.
    #
    my %param_values = %{ $fields_href };
    &AddSpecialDatasetVariables ($jconfig, \%param_values);

    my @arg_values = ();
    if ($jconfig->{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &SqlWithPlaceholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = map { $param_values{$_} } @variable_names;
        &Jarvis::Error::Debug ($jconfig, "Statement Args = " . join (",", map { (defined $_) ? "'$_'" : 'NULL' } @arg_values));

    } else {
        my $sql_with_variables = &SqlWithVariables ($sql, %param_values);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::Debug ($jconfig, "STORE = " . $sql);

    my $dbh = &Jarvis::DB::Handle ($jconfig);
    my $sth = $dbh->prepare ($sql)
        || &Jarvis::Error::MyDie ($jconfig, "Couldn't prepare statement '$sql': " . $dbh->errstr);

    # Execute
    my $num_rows = 0;
    eval {
        my $err_handler = $SIG{__DIE__};
        $SIG{__DIE__} = sub {};
        $num_rows = $sth->execute (@arg_values);
        $SIG{__DIE__} = $err_handler;
    };
    if ($@) {
        print STDERR "ERROR: Couldn't execute $transaction_type '$sql' with args '" . join ("','", map { $_ || 'NULL' } @arg_values) . "'\n";
        print STDERR $sth->errstr . "!\n";
        my $message = $sth->errstr;
        $sth->finish;

        if ($jconfig->{'format'} eq "json") {
            return "{ \"success\": 0, \"message\": \"" . &EscapeJavaScript (&Trim($message)) . "\"}";

        } else {
            my $xml = XML::Smart->new ();
            $xml->{success} = 0;
            $xml->{message} = &Trim($message);
            return $xml->data ();
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

    } else {
        my $xml = XML::Smart->new ();
        $xml->{success} = 1;
        $xml->{updated} = $num_rows;
        $returning && ($xml->{data}{row} = $rows_aref);

        return $xml->data ();
    }
}

1;
