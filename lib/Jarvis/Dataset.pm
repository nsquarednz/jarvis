###############################################################################
# Description:  Dataset access functions.  This is the core purpose of Jarvis,
#               to provide a front end to your database so that your ExtJS,
#               Adobe Flex, or other web application can have simple JSON or
#               XML web-service access to fetch and update data from your
#               back end SQL database on the server.
#
#               We currently support two different types of datasets:
#
#                   - DBI (via Perl DBI modules)
#                   - SDP (SSAS DataPump via SOAP and custom codec)
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

package Jarvis::Dataset;

use Data::Dumper;
use JSON::PP;
use XML::Smart;
use Text::CSV;
use IO::String;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;
use Jarvis::Hook;
use Jarvis::Dataset::DBI;
use Jarvis::Dataset::SDP;

###############################################################################
# Internal Functions
###############################################################################

################################################################################
# Loads the DataSet config from the config dir and returns it as XML.
#
#       $jconfig - Jarvis::Config object
#           READ
#               xml                 Find our app-configured "dataset_dir" dir.
#           WRITE
#               page_start_param    Name of the CGI param specifying page start row num
#               page_limit_param    Name of the CGI param specifying page limit row num
#               sort_field_param    Name of the CGI param specifying page sort field
#               sort_dir_param      Name of the CGI param specifying page sort direction
#
#       $subset_name - Name of single dataset file to load (may be a subset).
#
#   Note that a "." in a dataset name is a directory path.  Note that the
#   caller should NOT ever specify the ".xml" suffix, since we would confuse
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
    my ($jconfig, $subset_name) = @_;

    my $cgi = $jconfig->{"cgi"};

    # Determine the raw dataset name, before "." translation.
    &Jarvis::Error::debug ($jconfig, "Dataset Name '$subset_name' (as supplied).");

    ($subset_name =~ m/^\./) && die "Leading '.' not permitted on dataset name '$subset_name'";
    ($subset_name =~ m/\.$/) && die "Trailing '.' not permitted on dataset name '$subset_name'";

    # Find the best-matching "dataset_dir" prefix and use that directory.
    my $dsxml_filename = undef;
    my $subset_type = undef;
    my $best_prefix_len = -1;
        
    # Look at all our 'dataset_dir' entries.  They must all have a directory
    # as their inner content.  Also they may have a type (sdp or dbi), and
    # they can have a prefix which is a "." separated prefix on the incoming
    # dataset.  Note that any remaining "." that aren't stripped off by a prefix
    # match are treated as subdirectories inside the dataset dir.
    #
    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    $axml->{'dataset_dir'} || die "Missing configuration for mandatory element(s) 'dataset_dir'.";
    
    foreach my $dsdir ($axml->{'dataset_dir'}('@')) {
        my $dir = $dsdir->content || die "Missing directory in 'dataset_dir' element.";
        my $type = $dsdir->{'type'}->content || 'dbi';            
        my $prefix = $dsdir->{'prefix'}->content || '';
        
        # Non-empty prefix paths must end in a "." for matching purposes.
        if ($prefix && ($prefix =~ m/\.$/)) {
            $prefix .= ".";
        }
        my $prefix_len = length ($prefix);
        
        &Jarvis::Error::debug ($jconfig, "Dataset Directory: '$dir', type '$type', prefix '$prefix'.");
        if ($subset_name =~ m/^$prefix(.*)$/) {
            my $remainder = $1;
            $subset_type = $type;
            
            &Jarvis::Error::dump ($jconfig, "Prefix '$prefix' matched, length = " . $prefix_len);
            if ($prefix_len > $best_prefix_len) {
                $best_prefix_len = $prefix_len;
                
                # Now turn "." into "/" on the dataset name (with prefix stripped).
                $remainder =~ s/\./\//g;
                $dsxml_filename = "$dir/$remainder.xml";
                &Jarvis::Error::debug ($jconfig, "Using dataset directory '$dir', type '$type'.");
            }
        }
    }
    $dsxml_filename || die "No dataset_dir defined with prefix matching dataset '$subset_name'.";    

    # Load the dataset-specific XML file and double-check it has top-level <dataset> tag.
    &Jarvis::Error::debug ($jconfig, "Opening DSXML file '$dsxml_filename', type '$subset_type'.");

    # Check it exists.
    if (! -f $dsxml_filename) {
        $jconfig->{'status'} = '404 Not Found';
        die "No such DSXML file '$subset_name.xml' for application '" . $jconfig->{'app_name'} . "'";
    }

    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # Per-dataset DB name override default.
    $jconfig->{'subset_name'} = $subset_name;
    $jconfig->{'subset_type'} = $subset_type;
    $jconfig->{'subset_dbname'} = $dsxml->{'dataset'}{'dbname'}->content || "default";

    # Enable per dataset dump/debug
    $jconfig->{'dump'} = $jconfig->{'dump'} || defined ($Jarvis::Config::yes_value {lc ($dsxml->{'dataset'}{'dump'}->content || "no")});
    $jconfig->{'debug'} = $jconfig->{'debug'} || $jconfig->{'dump'} || defined ($Jarvis::Config::yes_value {lc ($dsxml->{'dataset'}{'debug'}->content || "no")});

    # Load a couple of other parameters.  This is a "side-effect".  Yeah, it's a bit yucky.
    $jconfig->{'page_start_param'} = $axml->{'page_start_param'}->content || 'page_start';
    $jconfig->{'page_limit_param'} = $axml->{'page_limit_param'}->content || 'page_limit';
    $jconfig->{'sort_field_param'} = $axml->{'sort_field_param'}->content || 'sort_field';
    $jconfig->{'sort_dir_param'} = $axml->{'sort_dir_param'}->content || 'sort_dir';

    # Load/Start dataset specific hooks.
    &Jarvis::Hook::start_dataset ($jconfig, $dsxml);

    return $dsxml;
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

    # Convert MS Word characters into their HTML equivalent.  This will stop
    # XML::Smart from attempting to encode them in base64.
    if ($$transforms_href{'word2html'}) {
        foreach my $key (keys %$vals_href) {
            next if ! defined $$vals_href{$key};
            $$vals_href{$key} = &word2html ($$vals_href{$key});
        }
    }

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
# Loads the data for the current dataset(s), and puts it into our return data
# hash so that it can be presented to the client in JSON.
#
# If the dataset is a comma-separated metaset, we perform multiple fetches
# and build the results into a larger object.
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
    
    # Handle multiple subsets, possibly.
    my @subsets = split (',', $jconfig->{'dataset_name'});
    if ((scalar @subsets) > 1) {
        if (($jconfig->{'format'} ne "json") && ($jconfig->{'format'} ne "xml")) {
            die "Multiple comma-separated datasets not supported for format '" . $jconfig->{'format'} . "'\n";
        }
    }
    
    # For JSON and XML we can build up nested responses.  This is the object used
    # to construct them piece by piece.
    my $all_results_object = undef;

    if ($jconfig->{'format'} eq "json") {
        $all_results_object = {};

    } elsif ($jconfig->{'format'} eq "xml") {
        $all_results_object = XML::Smart->new ();
    }
    
    # CSV files don't work with comma-separated datasets.
    if (($jconfig->{'format'} eq "csv") && ((scalar @subsets) > 1)) {
        die "CSV format not supported with multiple dataset names.";
    }

    # Handle our parameters.  Always with placeholders.  Note that our special variables
    # like __username are safe, and cannot come from user-defined values.
    #
    my %raw_params = $jconfig->{'cgi'}->Vars;
    my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%raw_params, $rest_args_aref);

    # Store the params for logging purposes.
    my %params_copy = %safe_params;
    $jconfig->{'params_href'} = \%params_copy;

    # Loop through each dataset file.  In most cases there is only one file.
    foreach my $subset_name (@subsets) {

        # Where will the return structure be placed?  For JSON/XML only.
        my $result_object = undef;

        # For JSON and XML, we store to an object and encode it at the end.
        if (defined $all_results_object) {

            # Multiple datasets.  Nest each dataset's results in a sub-structure.
            if ((scalar @subsets) > 1) {
                if ($jconfig->{'format'} eq "xml") {
                    $result_object = { 'name' => $subset_name };
                    push (@{ $all_results_object->{'response'}{'dataset'} }, $result_object);

                } elsif ($jconfig->{'format'} eq "json") {
                    $all_results_object->{'dataset'}{$subset_name} = {};
                    $result_object = $all_results_object->{'dataset'}{$subset_name};
                }


            # Single dataset.  This is backwards compatible with Jarvis 3.
            } else {
                if ($jconfig->{'format'} eq "xml") {
                    $result_object = $all_results_object->{'response'}

                } elsif ($jconfig->{'format'} eq "json") {
                    $result_object = $all_results_object;
                }
            }
        }

        # Load dataset definition.
        my $dsxml = &get_config_xml ($jconfig, $subset_name) || die "Cannot load configuration for dataset '$subset_name'.\n";

        # Check the allowed groups.
        my $allowed_groups = $dsxml->{dataset}{"read"};

        my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
        if ($failure ne '') {
            $jconfig->{'status'} = "401 Unauthorized";
            die "Insufficient privileges to read '$subset_name'. $failure\n";
        }    
 
        # Get a database handle.
        my $subset_type = $jconfig->{'subset_type'}; 
        my $subset_dbname = $jconfig->{'subset_dbname'}; 
        my $dbh = &Jarvis::DB::handle ($jconfig, $subset_dbname, $subset_type);
        
        # Get the data.        
        if ($subset_type eq 'dbi') {
            
            # Call to the DBI interface to fetch the tuples.
            my ($num_fetched, $rows_aref, $field_names_aref, $extra_href) 
                = &Jarvis::Dataset::DBI::fetch ($jconfig, $subset_name, $dsxml, $dbh, \%safe_params);
                
            # Store some additional info in jconfig for debugging/tracing.
            # These will refer to the most recent dataset being processed.
            $jconfig->{'fetched'} = $num_fetched;
            $jconfig->{'returned'} = scalar @$rows_aref;
            $jconfig->{'rows_aref'} = $rows_aref;
            $jconfig->{'field_names_aref'} = $field_names_aref;
        
            # Assemble the result object.
            #
            # NOTE: We always return a 'data' field, even if it is an empty array.
            # That is because ExtJS and other libraries will flag an exception if we do not.
            #
            foreach my $name (sort (keys %$extra_href)) {
                $result_object->{$name} = $extra_href->{$name};
            }
        
            $result_object->{'fetched'} = $num_fetched;                   # Fetched from database
            $result_object->{'returned'} = scalar @$rows_aref;         # Returned to client (after paging)
            
            # Subtle difference in the structure of returned XML vs. JSON.
            if ($jconfig->{'format'} eq "xml") {
                $result_object->{'data'}{'row'} = $rows_aref;
                
            } else {
                $result_object->{'data'} = $rows_aref;
            }
    
        } else {
            die "Unrecognized type '$subset_type' for dataset '$subset_name' on fetch.";
        }
    }

    # Standard case.  JSON/XML format.  Encode to text and return it.
    my $return_value;
    my $extra_href = {};
    &Jarvis::Hook::return_fetch ($jconfig, \%safe_params, $all_results_object, $extra_href, \$return_value);

    # If the hook performed its own encoding, we have no further work to do.
    if ($return_value) {
        &Jarvis::Error::debug ($jconfig, "Return content determined by hook ::return_fetch");
        
    # This is for INTERNAL use only!  Plugins for example might like to get the raw hash
    # and do their own formatting.  If you try this from a browser, you're going to
    # get something nasty happening.  Note also that this only works for a single dataset,
    # if you try it with a comma-separated list of datasets, you'll simply get the rows_aref
    # for the LAST dataset in the list.
    #
    } elsif ($jconfig->{'format'} eq "rows_aref") {
        &Jarvis::Error::debug ($jconfig, "Return rows_aref in raw format.");
        $return_value = $jconfig->{'rows_aref'};
        
    # JSON encoding is now simple.
    } elsif ($jconfig->{'format'} eq "json") {
        &Jarvis::Error::debug ($jconfig, "Encoding into JSON format.");

        $all_results_object->{'logged_in'} = $jconfig->{'logged_in'};
        $all_results_object->{'username'} = $jconfig->{'username'};
        $all_results_object->{'error_string'} = $jconfig->{'error_string'};
        $all_results_object->{'group_list'} = $jconfig->{'group_list'};

        # Copy across any extra root parameters set by the return_fetch hook.
        foreach my $name (sort (keys %$extra_href)) {
            $all_results_object->{$name} = $extra_href->{$name};
        }

        my $json = JSON::PP->new->pretty(1);
        $return_value = $json->encode ( $all_results_object );

    # XML is also simple.
    } elsif ($jconfig->{'format'} eq "xml") {
        &Jarvis::Error::debug ($jconfig, "Encoding into XML format.");

        $all_results_object->{'response'}{'logged_in'} = $jconfig->{'logged_in'};
        $all_results_object->{'response'}{'username'} = $jconfig->{'username'};
        $all_results_object->{'response'}{'error_string'} = $jconfig->{'error_string'};
        $all_results_object->{'response'}{'group_list'} = $jconfig->{'group_list'};

        # Copy across any extra root parameters set by the return_fetch hook.
        foreach my $name (sort (keys %$extra_href)) {
            $all_results_object->{'response'}{$name} = $extra_href->{$name};
        }

        $return_value = $all_results_object->data ();

    # CSV format is the trickiest.  Note that it is dependent on the $sth->{NAME} data
    # being available.  This field is absent in the following cases at least:
    #
    #  - Some (all?) stored procedures under MS SQL.
    #  - Pivot queries under MS SQL.
    #  - SqlLite database.
    #
    # In such case, you will need to write a "smart" plugin which can figure out 
    # the field names itself, access the data with "rows_aref" format, and
    # put two and two together.
    # 
    # Or alternative, we could extend the dataset definition to allow you to
    # configure the column names.  Or a post-fetch hook could fake them up.
    #
    } elsif ($jconfig->{'format'} eq "csv") {
        &Jarvis::Error::debug ($jconfig, "Encoding into CSV format.");

        # Check we have the data we need.
        my $field_names_aref = $jconfig->{'field_names_aref'};
        my $rows_aref = $jconfig->{'rows_aref'};
        
        if (! $rows_aref) {
            die "Data query did not include a return result.  Cannot convert to CSV.";
        }
        if (! $field_names_aref || ! (scalar @$field_names_aref)) {
            die "Data query did not return column names.  Cannot convert to CSV.";
        }
        
        my %field_index = ();
        @field_index { @$field_names_aref } = (0 .. $#$field_names_aref);

        # Create a string IO handle to print CSV into.
        my $csv_return_text = '';
        my $io = IO::String->new ($csv_return_text);

        # Create a CSV object and print the header line.
        my $csv = Text::CSV->new ( { binary => 1 } );
        $csv->print ($io, $field_names_aref);
        print $io "\n";

        # Now print the data.
        foreach my $row_href (@$rows_aref) {
            my @columns = map { $$row_href{$_} } @$field_names_aref;
            $csv->print ($io, \@columns);
            print $io "\n";
        }

        $return_value = $csv_return_text;
        
    } else {
        die "Unsupported format.  Cannot encode into '" . $jconfig->{'format'} ."' for Dataset::fetch return data.\n";
    }

    # Debugging for "text" return values.
    if ((ref $return_value) eq 'SCALAR') {
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($return_value));
        &Jarvis::Error::dump ($jconfig, $return_value);
    }
    
    return $return_value;        
}

################################################################################
# Performs an update to the specified table underlying the named dataset.
# This is currently only supported for DBI datasets.
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

    # The dataset may only contain ONE single subset.    
    my $dataset_name = $jconfig->{'dataset_name'} || '';
    ($dataset_name =~ m/,/) && die "Multiple comma-separated datasets not permitted with store operations.";
    my $subset_name = $dataset_name;
    
    # Read the dataset config file.  This fills some $jconfig fields as a side-effect.
    my $dsxml = &get_config_xml ($jconfig, $subset_name) || die "Cannot load configuration for dataset '$subset_name'.";
    
    # Check that we are DBI only.
    my $dataset_type = $jconfig->{'subset_type'}; 
    ($dataset_type eq 'dbi') || die "Datasets of type '$dataset_type' do not support store operations.";

    # Now perform security check.
    my $allowed_groups = $dsxml->{dataset}{"write"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{'status'} = "401 Unauthorized";
        die "Insufficient privileges to write '$subset_name'. $failure\n";
    }
    
    # Get a database handle.
    my $subset_type = $jconfig->{'subset_type'}; 
    my $subset_dbname = $jconfig->{'subset_dbname'}; 
    my $dbh = &Jarvis::DB::handle ($jconfig, $subset_dbname, $subset_type);
    
    # Hand off to DBI code.  Maybe one day we will support different dataset
    # types for "store" operations, in which case some more of the common
    # pre-processing and results encoding code may move from the DBI module
    # up into this one.  Until then, let's just let sleeping dogs lie.
    return &Jarvis::Dataset::DBI::store ($jconfig, $subset_name, $dsxml, $dbh, $rest_args_aref);
}

1;
