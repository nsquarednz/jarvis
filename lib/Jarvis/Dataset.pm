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
# Deprecated Functions
###############################################################################

# These should never be called by external functions.  You should use a hook
# if you need to tinker with these.  But if you HAVE to use them, please 
# reference the versions in Jarvis::Dataset::DBI so that we can remove these
# pass through functions ASAP.

sub parse_statement {
    return &Jarvis::Dataset::DBI::parse_statement (@_);
}
sub statement_execute {
    return &Jarvis::Dataset::DBI::statement_execute (@_);
}

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
    my $default_dbname = undef;
        
    # Look at all our 'dataset_dir' entries.  They must all have a directory
    # as their inner content.  Also they may have a type (sdp or dbi), and
    # they can have a prefix which is a "." separated prefix on the incoming
    # dataset.  Note that any remaining "." that aren't stripped off by a prefix
    # match are treated as subdirectories inside the dataset dir.
    #
    my $axml = $jconfig->{'xml'}{'jarvis'}{'app'};
    $axml->{'dataset_dir'} || die "Missing configuration for mandatory element(s) 'dataset_dir'.";
    
    # Check for duplicate prefixes.
    my %prefix_seen = ();
    
    foreach my $dsdir ($axml->{'dataset_dir'}('@')) {
        my $dir = $dsdir->content || die "Missing directory in 'dataset_dir' element.";
        my $type = $dsdir->{'type'}->content || 'dbi';            
        my $prefix = $dsdir->{'prefix'}->content || '';
        my $dbname = $dsdir->{'dbname'}->content || 'default';
        
        # Non-empty prefix paths must end in a "." for matching purposes.
        if ($prefix && ($prefix !~ m/\.$/)) {
            $prefix .= ".";
        }
        my $prefix_len = length ($prefix);

        $prefix_seen{$prefix}++ && die "Duplicate dataset_dir entries for prefix '$prefix' are defined.";             
        
        &Jarvis::Error::debug ($jconfig, "Dataset Directory: '$dir', type '$type', prefix '$prefix', dbname '$dbname'.");
        if ($subset_name =~ m/^$prefix(.*)$/) {
            my $remainder = $1;
            
            &Jarvis::Error::dump ($jconfig, "Prefix '$prefix' matched, length = " . $prefix_len);
            if ($prefix_len > $best_prefix_len) {
                $best_prefix_len = $prefix_len;
                $subset_type = $type;
                
                # Now turn "." into "/" on the dataset name (with prefix stripped).
                $remainder =~ s/\./\//g;
                $dsxml_filename = "$dir/$remainder.xml";
                $default_dbname = $dbname;
                &Jarvis::Error::debug ($jconfig, "Using dataset directory '$dir', type '$type', default dbname '$dbname'.");
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
    $jconfig->{'subset_dbname'} = $dsxml->{'dataset'}{'dbname'}->content || $default_dbname;

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
# Gets our POSTDATA from a number of potential difference sources.  Stores it
# in $jconfig, just in case it is needed later.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
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
#               format              Either "json", "json.array", "xml", "csv", 
#                                   "xlsx", or "rows_aref".
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
    
    my $format = $jconfig->{'format'};
    
    # Handle multiple subsets, possibly.
    my @subsets = split (',', $jconfig->{'dataset_name'});
    if ((scalar @subsets) > 1) {
        if (($format !~ m/^json/) && ($format !~ m/^xml/)) {
            die "Multiple comma-separated datasets not supported for format '" . $format . "'\n";
        }
    }
    
    # For JSON and XML we can build up nested responses.  This is the object used
    # to construct them piece by piece.
    my $all_results_object = undef;

    if ($format =~ m/^json/) {
        $all_results_object = {};

    } elsif ($format =~ m/^xml/) {
        $all_results_object = XML::Smart->new ();
    }
    
    # CSV (and other spreadsheet formats) no workee with comma-separated datasets.
    if ((($format eq "csv") || ($format eq "xlsx")) && ((scalar @subsets) > 1)) {
        die "Format '$format' not supported with multiple dataset names.";
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
                if ($format =~ m/^xml/) {
                    $result_object = { 'name' => $subset_name };
                    push (@{ $all_results_object->{'response'}{'dataset'} }, $result_object);

                } elsif ($format =~ m/^json/) {
                    $all_results_object->{'dataset'}{$subset_name} = {};
                    $result_object = $all_results_object->{'dataset'}{$subset_name};
                }


            # Single dataset.  This is backwards compatible with Jarvis 3.
            } else {
                if ($format =~ m/^xml/) {
                    $result_object = $all_results_object->{'response'}

                } elsif ($format =~ m/^json/) {
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

        # What filename would this dataset use?
        my $filename_parameter = $dsxml->{'dataset'}{'filename_parameter'}->content || 'filename';
        &Jarvis::Error::debug ($jconfig, "Filename parameter = '$filename_parameter'.");        
        $jconfig->{'return_filename'} = $safe_params {$filename_parameter} || '';        
        &Jarvis::Error::debug ($jconfig, "Return filename = '" . $jconfig->{'return_filename'} . "'.");        
        
        # Get a database handle.
        my $subset_type = $jconfig->{'subset_type'}; 
        my $subset_dbname = $jconfig->{'subset_dbname'}; 
        my $dbh = &Jarvis::DB::handle ($jconfig, $subset_dbname, $subset_type);
        
        # Get the data.  Note that this is the very first time in fetch processing
        # that we have performed an EXACT match on the requested format.  Until
        # now, we have only validated the prefix part (e.g. json*, xml*).  Now
        # we will be fussy about the exact requested return format. 
        #
        if (($format eq 'xml') || ($format eq 'xml.array') || 
            ($format eq 'json') || ($format eq 'json.array') || 
            ($format eq 'csv') || ($format eq 'xlsx') || ($format eq 'rows_aref')) {
            
            # Call to the DBI interface to fetch the tuples.
            my ($rows_aref, $column_names_aref);
            
            if ($subset_type eq 'dbi') {
                ($rows_aref, $column_names_aref) 
                    = &Jarvis::Dataset::DBI::fetch ($jconfig, $subset_name, $dsxml, $dbh, \%safe_params);
                    
            } elsif ($subset_type eq 'sdp') {
                ($rows_aref, $column_names_aref) 
                    = &Jarvis::Dataset::SDP::fetch ($jconfig, $subset_name, $dsxml, $dbh, \%safe_params);
                    
            } else {
                die "Unrecognised dataset type '$subset_type' in fetch of format '$format'.";
            }
            
            # Now we have an array of hash objects.
            my $num_fetched = scalar @$rows_aref;
            &Jarvis::Error::debug ($jconfig, "Number of rows fetched = $num_fetched.");
        
            # Do we want to do server side sorting?  This happens BEFORE paging.  Note that this
            # will only work when $sth->{NAME} is available.  Some (all?) stored procedures
            # under MS-SQL Server will not provide field names, and hence this feature will not
            # be available.
            #
            my $sort_field = $jconfig->{'cgi'}->param ($jconfig->{'sort_field_param'}) || '';
            my $sort_dir = $jconfig->{'cgi'}->param ($jconfig->{'sort_dir_param'}) || 'ASC';
        
            if ($sort_field) {
                &Jarvis::Error::debug ($jconfig, "Server Sort on '$sort_field', Dir = '$sort_dir'.");
        
                if (! grep { /$sort_field/ } @$column_names_aref) {
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
        
                &Jarvis::Error::debug ($jconfig, "Limit = $limit, Offset = $start, Num Rows = $num_fetched.");
        
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
        
            # Store the number of returned rows for the current dataset in the list.
            $jconfig->{'out_nrows'} = scalar @$rows_aref;
        
            # What transformations should we use when sending out fetch data?
            my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->{dataset}{transform}{fetch});
            &Jarvis::Error::debug ($jconfig, "Fetch transformations = " . join (', ', keys %transforms) . " (applied to returned results)");
        
            # Apply any output transformations to remaining hashes.
            if (scalar (keys %transforms)) {
                foreach my $row_href (@$rows_aref) {
                    &Jarvis::Dataset::transform (\%transforms, $row_href);
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
            
            # This final hook allows you to modify the data returned by SQL for one dataset.
            # This hook may do one or both of:
            #
            #   - Completely modify the returned content (by modifying $rows_aref)
            #   - Add additional per-dataset scalar parameters (by setting $extra_href)
            #
            my $extra_href = {};
            &Jarvis::Hook::dataset_fetched ($jconfig, $dsxml, \%safe_params, $rows_aref, $column_names_aref, $extra_href);
                    
            # Store some additional info in jconfig for debugging/tracing.
            # These will refer to the most recent dataset being processed.
            $jconfig->{'fetched'} = $num_fetched;
            $jconfig->{'returned'} = scalar @$rows_aref;
            $jconfig->{'rows_aref'} = $rows_aref;
            $jconfig->{'column_names_aref'} = $column_names_aref;
        
            # Assemble the result object.
            #
            # NOTE: We always return a 'data' field, even if it is an empty array.
            # That is because ExtJS and other libraries will flag an exception if we do not.
            #
            foreach my $name (sort (keys %$extra_href)) {
                $result_object->{$name} = $extra_href->{$name};
            }
        
            $result_object->{'fetched'} = 1 * $num_fetched;                   # Fetched from database
            $result_object->{'returned'} = scalar @$rows_aref;         # Returned to client (after paging)
            
            # XML encoding in its simplest form.  Column keys are attributes.
            if ($format eq "xml") {
                $result_object->{'data'}{'row'} = $rows_aref;
                
            # XML array is a funny sort of mish-mash.
            } elsif ($format eq "xml.array") {
                my $i = 0;
                my @column_objects = map { {'index' => $i++, 'name' => $_} } @$column_names_aref;
                $result_object->{'columns'}{'header'} = \@column_objects;

                # Convert the hashes into rows.
                my @rows2;
                foreach my $row (@$rows_aref) {
                    my $i = 0;
                    my @column_objects = map { (defined $row->{$_}) ? {'index' => $i++, 'value' => $row->{$_} } : {'index' => $i++, 'null' => '1' } } @$column_names_aref;
                    push (@rows2, {'column' => \@column_objects});
                }
                $result_object->{'data'}{'row'} = \@rows2;
                
            # JSON array is array of arrays.                
            } elsif ($format eq "json.array") {
                $result_object->{'columns'} = $column_names_aref;
                
                # Convert the hashes into rows.
                my @rows2;
                foreach my $row (@$rows_aref) {
                    my @row2 = map { (defined $row->{$_}) ? $row->{$_} : undef } @$column_names_aref;
                    push (@rows2, \@row2);
                }
                $result_object->{'data'} = \@rows2;

            # Note the JSON object is also temporary store for CSV and rows_aref. 
            } else {
                $result_object->{'data'} = $rows_aref;
            }
            
        } else {
            die "No implementation for fetch format '$format', dataset '$subset_name'.";
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
    } elsif ($format eq "rows_aref") {
        &Jarvis::Error::debug ($jconfig, "Return rows_aref in raw format.");
        $return_value = $jconfig->{'rows_aref'};
        
    # JSON encoding is now simple.
    } elsif (($format eq "json") || ($format eq "json.array")) {
        &Jarvis::Error::debug ($jconfig, "Encoding into JSON format.");

        $all_results_object->{'logged_in'} = $jconfig->{'logged_in'} ? 1 : 0;
        $all_results_object->{'username'} = $jconfig->{'username'};
        $all_results_object->{'error_string'} = $jconfig->{'error_string'};
        $all_results_object->{'group_list'} = $jconfig->{'group_list'};

        # Copy across any extra root parameters set by the return_fetch hook.
        foreach my $name (sort (keys %$extra_href)) {
            $all_results_object->{$name} = $extra_href->{$name};
        }

        my $json = JSON::PP->new->pretty(1)->allow_blessed(1);
        $return_value = $json->encode ( $all_results_object );

    # XML is also simple.
    } elsif (($format eq "xml") || ($format eq "xml.array")) {
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

    # CSV format tricky.  Note that it is dependent on the $sth->{NAME} data
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
    } elsif ($format eq "csv") {
        &Jarvis::Error::debug ($jconfig, "Encoding into CSV format.");

        # Check we have the data we need.
        my $column_names_aref = $jconfig->{'column_names_aref'};
        my $rows_aref = $jconfig->{'rows_aref'};
        
        if (! $rows_aref) {
            die "Data query did not include a return result.  Cannot convert to CSV.";
        }
        if (! $column_names_aref || ! (scalar @$column_names_aref)) {
            die "Data query did not return column names.  Cannot convert to CSV.";
        }
        
        my %field_index = ();
        @field_index { @$column_names_aref } = (0 .. $#$column_names_aref);

        # Create a string IO handle to print CSV into.
        my $csv_return_text = '';
        my $io = IO::String->new ($csv_return_text);

        # Create a CSV object and print the header line.
        my $csv = Text::CSV->new ( { binary => 1 } );
        $csv->print ($io, $column_names_aref);
        print $io "\n";

        # Now print the data.
        foreach my $row_href (@$rows_aref) {
            my @columns = map { $$row_href{$_} } @$column_names_aref;
            $csv->print ($io, \@columns);
            print $io "\n";
        }

        $return_value = $csv_return_text;
        
    # XLSX is basically the same as CSV, but with different encoding.
    #
    } elsif ($format eq "xlsx") {
        &Jarvis::Error::debug ($jconfig, "Encoding into XLSX format.");

        # Dynamically load this module.
        require Excel::Writer::XLSX;
        
        # Check we have the data we need.
        my $column_names_aref = $jconfig->{'column_names_aref'};
        my $rows_aref = $jconfig->{'rows_aref'};
        
        if (! $rows_aref) {
            die "Data query did not include a return result.  Cannot convert to XLSX.";
        }
        if (! $column_names_aref || ! (scalar @$column_names_aref)) {
            die "Data query did not return column names.  Cannot convert to XLSX.";
        }
        
        my %field_index = ();
        @field_index { @$column_names_aref } = (0 .. $#$column_names_aref);

        # Create an IO buffer.
        my $xlsx_return_text = '';
        my $io = IO::String->new ($xlsx_return_text);

        my $workbook = Excel::Writer::XLSX->new ($io);
        my $size = 10;
        my $default_format = $workbook->add_format (font => 'Arial', size => $size);
        my $worksheet = $workbook->add_worksheet ();
        
        my ($row, $col) = (0, 0);
        foreach my $column_name (@$column_names_aref) {
            $worksheet->write ($row, $col++, $column_name, $default_format);
        }
        $row++;

        foreach my $row_href (@$rows_aref) {
            $col = 0;
            my @columns = map { $$row_href{$_} } @$column_names_aref;
            foreach my $value (@columns) {
                $worksheet->write ($row, $col++, $value, $default_format);
            }
            $row++;
        }        
        $workbook->close(); 
        
        $return_value = $xlsx_return_text;

    } else {
        die "Unsupported format.  Cannot encode into '$format' for Dataset::fetch return data.\n";
    }

    # Debugging for "text" return values.
    if ((ref \$return_value) eq 'SCALAR') {
        &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($return_value));
        &Jarvis::Error::dump ($jconfig, $return_value) unless ($format eq "xlsx");
    } else {
        &Jarvis::Error::debug ($jconfig, "type (return_value) = " . (ref \$return_value));
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
#               format              Either "json", "json.array", or "xml".
#                                   Not allowed "csv" or "rows_aref".
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
    # up into this one.  
    # 
    # See the "fetch" method above for a good example of how that should work.
    # Most of the pre-processing and hook invocation should be here in 
    # Dataset.pm, and only the DBI specific stuff should be in DBI.pm.
    #
    # But until then, let's just let sleeping dogs lie.
    return &Jarvis::Dataset::DBI::store ($jconfig, $subset_name, $dsxml, $dbh, $rest_args_aref);
}

1;
