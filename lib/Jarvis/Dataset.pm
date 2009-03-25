###############################################################################
# Description:  Functions for creating dojo helper JS for grid widgets.
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

my %yes_value = ('yes' => 1, 'true' => 1, '1' => 1);

###############################################################################
# Internal Functions
###############################################################################

################################################################################
# Loads the DataSet config from the config dir and returns it as XML.
#
# Params: Hash of Args (* indicates mandatory)
#       *config_dir, *app_name, *dataset_name
#
# Returns:
#       $dsxml - XML::Smart object holding config info read from file.
################################################################################
#
sub GetConfigXML {
    my ($args_href) = @_;

    my $cgi = $$args_href {"cgi"};
    my $config_dir = $$args_href {"config_dir"};
    my $app_name = $$args_href {"app_name"};

    # Now we require 'dataset' to also be a CGI parameter.
    my $dataset_name = $cgi->param ('dataset') || die "Missing mandatory parameter 'dataset'!\n";
    ($dataset_name =~ m/^\w+$/) || die "Invalid characters in parameter 'dataset'\n";
    $$args_href{"dataset_name"} = $dataset_name;

    # Load the dataset-specific XML file.
    my $dsxml_filename = "$config_dir/$app_name/$dataset_name.xml";
    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # Now we have dataset config.  Add to our list of args.
    return $dsxml;
}

################################################################################
# Checks that a given dataset grants access to the currently logged in user
# or the current public (non-logged-in) user.
#
#    ""   -> Allow nobody at all.
#    "**" -> Allow all and sundry.
#    "*"  -> Allow all logged-in users.
#    "group,[group]"  -> Allow those in one (or more) of the named groups.
#
# Params:
#       Permission ("read" or "write")
#       Hash of Args (* indicates mandatory)
#               logged_in, user_name, group_list
#
# Returns:
#       1.
#       die on error.
################################################################################
#
sub CheckAccess {
    my ($permission, $dsxml, %args) = @_;

    # Check permissions
    my $allowed_groups = $dsxml->{dataset}{$permission};
    if ($allowed_groups eq "") {
        &Jarvis::Error::MyDie ("This dataset does not allow $permission to anybody.\n", %args);

    } elsif ($allowed_groups eq "**") {
        # Allow access to all even those not logged in.

    } elsif ($allowed_groups eq "*") {
        $args{'logged_in'} || &Jarvis::Error::MyDie ("Successful login is required in order to $permission this dataset.\n", %args);

    } else {
        my $allowed = 0;
        foreach my $allowed_group (split (',', $allowed_groups)) {
            foreach my $member_group (split (',', $args{'group_list'})) {
                if ($allowed_group eq $member_group) {
                    $allowed = 1;
                    last;
                }
            }
            last if $allowed;
        }
        $allowed || &Jarvis::Error::MyDie ("Logged-in user does not belong to any of the permitted $permission groups.\n", %args);
    }

    1;
}

################################################################################
# Get the SQL for the update, insert, and delete.
#
# Params:
#       SQL Type ("fetch", "insert", "update", "delete")
#       XML::Smart object for dataset configuration
#       Hash of Args (* indicates mandatory)
#
# Returns:
#       ($sql, @variable_names).
#       die on error.
################################################################################
#
sub GetSQL {
    my ($which, $dsxml, %args) = @_;

    my $sql = $dsxml->{dataset}{$which}->content;
    $sql || &Jarvis::Error::MyDie ("This dataset has no SQL of type '$which'.", %args);
    $sql = &Trim ($sql);

    return $sql;
}

################################################################################
# Adds some special variables to our name -> value map.
#
#   __username  -> <logged-in-username>
#   __grouplist -> ('<group1>', '<group2>', ...)
#   __group:<groupname>  ->  1 (iff belong to <groupname>) or NULL
#
# Params:
#       $param_values_href
#       Hash of Args (* indicates mandatory)
#               user_name, group_list
#
# Returns:
#       1
################################################################################
#
sub AddSpecialVariables {

    my ($param_values_href, %args) = @_;

    # These are defined if we have logged in.
    if (defined $args{'user_name'}) {
        $$param_values_href{"__username"} = $args{'user_name'};
    }
    if (defined $args{'group_list'}) {
        $$param_values_href{"__grouplist"} = "('" . join ("',", $args{'group_list'} || '') . "')";
        foreach my $group (split (',', $args{'group_list'})) {
            $$param_values_href{"__group:$group"} = 1;
        }
    }

    # These can be passed by the client, we just set defaults if needed.
    $$param_values_href{"__max_rows"} || ($$param_values_href{"__max_rows"} = $args{'max_rows'});
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
# Params: Hash of Args (* indicates mandatory)
#       *dbh, *logged_in, user_name, group_list
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub Fetch {
    my (%args) = @_;

    my $dsxml = &GetConfigXML (\%args) || die "Cannot load configuration for dataset.\n";
    &CheckAccess ("read", $dsxml, %args);

    my $sql = &GetSQL ('select', $dsxml, %args);

    # Handle our parameters.  Either inline or with placeholders.
    my %param_values = $args{'cgi'}->Vars;
    &AddSpecialVariables (\%param_values, %args);

    my @arg_values = ();
    if ($args{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &SqlWithPlaceholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = map { $param_values{$_} } @variable_names;

    } else {
        my $sql_with_variables = &SqlWithVariables ($sql, %param_values);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::Debug ("FETCH = " . $sql, %args);

    my $sth = $args{'dbh'}->prepare ($sql)
        || &Jarvis::Error::MyDie ("Couldn't prepare statement '$sql': " . $args{'dbh'}->errstr, %args);

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
    if ($args{'format'} eq "json") {
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
# Params: Hash of Args
#       *cgi, *user_name, *dbh
#
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub Store {
    my (%args) = @_;

    my $dsxml = &GetConfigXML (\%args) || die "Cannot load configuration for dataset.\n";
    &CheckAccess ("write", $dsxml, %args);

    # Figure out what field is our "serial" ID.  Normally it is "id", but it
    # could change.
    my $serial_name = $dsxml->{dataset}{serial};
    $serial_name || &Jarvis::Error::MyDie ("This dataset has no serial ID parameter.", %args);

    # Check we have some changes and parse 'em from the JSON.  We get an
    # array of hashes.  Each array entry is a change record.
    my $changes_json = $args{'cgi'}->param ('fields')
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
            || &Jarvis::Error::MyDie ("Cannot delete entry with missing serial.", %args);

        $sql = &GetSQL ('delete', $dsxml, %args);

    # Update => INSERT or UPDATE.
    } elsif ($transaction_type eq "update") {
        if ((defined $serial_value) && ($serial_value > 0)) {
            $sql = &GetSQL ('update', $dsxml, %args);

        } else {
            $sql = &GetSQL ('insert', $dsxml, %args);
            $returning = defined ($yes_value {lc ($dsxml->{dataset}{'insert'}{'returning'} || "no")});
            &Jarvis::Error::Debug ("Insert Returning = " . $returning, %args);
        }

    } else {
        &Jarvis::Error::MyDie ("Unsupported transaction type '$transaction_type'.", %args);
    }

    # Handle our parameters.  Either inline or with placeholders.
    my %param_values = %{ $fields_href };
    &AddSpecialVariables (\%param_values, %args);

    my @arg_values = ();
    if ($args{'use_placeholders'}) {
        my ($sql_with_placeholders, @variable_names) = &SqlWithPlaceholders ($sql);

        $sql = $sql_with_placeholders;
        @arg_values = map { $param_values{$_} } @variable_names;
        &Jarvis::Error::Debug ("Statement Args = '" . join ("','", @arg_values) . "'", %args);

    } else {
        my $sql_with_variables = &SqlWithVariables ($sql, %param_values);
        $sql = $sql_with_variables;
    }

    # Prepare
    &Jarvis::Error::Debug ("STORE = " . $sql, %args);

    my $sth = $args{'dbh'}->prepare ($sql)
        || &Jarvis::Error::MyDie ("Couldn't prepare statement '$sql': " . $args{'dbh'}->errstr, %args);

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

        if ($args{'format'} eq "json") {
            return "{ \"success\": 0, \"message\": \"" . &EscapeJavaScript (&Trim($message)) . "\"}";

        } else {
            $xml->{success} = 0;
            $xml->{message} = &Trim($message);
            return $xml->data ();
        }
    }

    # Fetch the results, if this INSERT indicates that it returns values.
    my $rows_aref = $returning ? $sth->fetchall_arrayref({}) : undef;
    $sth->finish;

    # Return content in requested format.
    if ($args{'format'} eq "json") {
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
