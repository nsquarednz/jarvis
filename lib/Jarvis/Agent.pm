###############################################################################
# Description:  Dataset access functions base class.
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

package Jarvis::Agent;

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

    return undef;
}
sub transaction_rollback {
    my ($class, $jconfig, $dbh) = @_;

    return undef;
}
sub transaction_commit {
    my ($class, $jconfig, $dbh) = @_;

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
#               cgi                 Contains data values for {{param}} in MDX
#               username            Used for {{username}} in MDX
#               group_list          Used for {{group_list}} in MDX
#               format              Either "json" or "xml" or "csv".
#
#       $dataset_name - Name of single dataset we are fetching from.
#       $dsxml - Dataset's XML configuration object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $safe_params_href - All our safe parameters.
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
################################################################################
sub fetch_inner {
    my ($class, $jconfig, $dataset_name, $dsxml, $dbh, $safe_params_href) = @_;

    die "This agent does not implement 'fetch' methods.";
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

    die "This agent does not implement 'before' statements.";
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

    die "This agent does not implement 'store' methods.";
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

    die "This agent does not implement 'after' statements.";
}

1;