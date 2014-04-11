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
use JSON;
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
# Loads the DataSet config from the config dir.  This will push a dataset 
# descriptor onto the dataset stack (and return it).
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
#       $dataset_name - Name of dataset file to load.
#
#   Note that a "." in a dataset name is a directory path.  Note that the
#   caller should NOT ever specify the ".xml" suffix, since we would confuse
#   "test.xml" for "<dataset_dir>/test/xml.xml".  And that would be bad.
#
#   Note that it is OUR job to check that the path is safe before opening
#   the file.
#
# Returns:
#       Top element from $jconfig->{datasets}
#       {
#           level => 0+             # 0 = Master dataset.  1 = child, 2 = grandchild, etc.
#           name => $dataset_name,  
#           dsxml => $dsxml,        # XML::Smart object holding config info read from file
#           dbtype => 'dbi'/'sdp'
#           dbname => $dbname,      # Key into Jarvis app <database> list
#   
#           # These are extended from global defaults and/or previous stack level.
#           debug => 0/1,           # Current debug flag at this level
#           dump => 0/1,            # Current dump flag at this level
#
#           # These are present ONLY for top-level (level = 0), the only level which supports paging.
#           page_start_param => 'page_start',  # or override
#           page_limit_param => 'page_limit',  # or override value
#           sort_field_param => 'sort_field'   # or override value
#           sort_dir_param => 'sort_dir'       # or override value
#       }
################################################################################
#
sub load_dsxml {
    my ($jconfig, $dataset_name) = @_;

    # Determine the raw dataset name, before "." translation.
    &Jarvis::Error::debug ($jconfig, "Loading DSXML for '$dataset_name'.");

    ($dataset_name =~ m/^\./) && die "Leading '.' not permitted on dataset name '$dataset_name'";
    ($dataset_name =~ m/\.$/) && die "Trailing '.' not permitted on dataset name '$dataset_name'";

    # Find the best-matching "dataset_dir" prefix and use that directory.
    my $dsxml_filename = undef;
    my $dbtype = undef;
    my $best_prefix_len = -1;
    my $default_dbname = undef;
        
    # Look at all our 'dataset_dir' entries.  They must all have a directory
    # as their inner content.  Also they may have a type (sdp or dbi), and
    # they can have a prefix which is a "." separated prefix on the incoming
    # dataset.  Note that any remaining "." that aren't stripped off by a prefix
    # match are treated as subdirectories inside the dataset dir.
    #
    my $axml = $jconfig->{xml}{jarvis}{app};
    $axml->{dataset_dir} || die "Missing configuration for mandatory element(s) 'dataset_dir'.";
    
    # Check for duplicate prefixes.
    my %prefix_seen = ();
    
    foreach my $dsdir ($axml->{dataset_dir}('@')) {
        my $dir = $dsdir->content || die "Missing directory in 'dataset_dir' element.";
        my $type = $dsdir->{type}->content || 'dbi';            
        my $prefix = $dsdir->{prefix}->content || '';
        my $dbname = $dsdir->{dbname}->content || 'default';
        
        # Non-empty prefix paths must end in a "." for matching purposes.
        if ($prefix && ($prefix !~ m/\.$/)) {
            $prefix .= ".";
        }
        my $prefix_len = length ($prefix);

        $prefix_seen{$prefix}++ && die "Duplicate dataset_dir entries for prefix '$prefix' are defined.";             
        
        &Jarvis::Error::debug ($jconfig, "Dataset Directory: '$dir', type '$type', prefix '$prefix', dbname '$dbname'.");
        if ($dataset_name =~ m/^$prefix(.*)$/) {
            my $remainder = $1;
            
            &Jarvis::Error::dump ($jconfig, "Prefix '$prefix' matched, length = " . $prefix_len);
            if ($prefix_len > $best_prefix_len) {
                $best_prefix_len = $prefix_len;
                $dbtype = $type;
                
                # Now turn "." into "/" on the dataset name (with prefix stripped).
                $remainder =~ s/\./\//g;
                $dsxml_filename = "$dir/$remainder.xml";
                $default_dbname = $dbname;
                &Jarvis::Error::debug ($jconfig, "Using dataset directory '$dir', type '$type', default dbname '$dbname'.");
            }
        }
    }
    $dsxml_filename || die "No dataset_dir defined with prefix matching dataset '$dataset_name'.";    

    # Load the dataset-specific XML file and double-check it has top-level <dataset> tag.
    &Jarvis::Error::debug ($jconfig, "Opening DSXML file '$dsxml_filename', type '$dbtype'.");

    # Check it exists.
    if (! -f $dsxml_filename) {
        $jconfig->{status} = '404 Not Found';
        die "No such DSXML file '$dataset_name.xml' for application '" . $jconfig->{app_name} . "'";
    }

    my $dsxml = XML::Smart->new ("$dsxml_filename") || die "Cannot read '$dsxml_filename': $!\n";
    ($dsxml->{dataset}) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # What kind of database are we dealing with?
    my $dbname = $dsxml->{dataset}{dbname}->content || $default_dbname;

    # What dataset level are we at in our stack?  Level 0 is the top-level, master dataset.  Others are childs.
    (defined $jconfig->{datasets}) || ($jconfig->{datasets} = []);
    my $level = scalar @{ $jconfig->{datasets} };

    # Does this dataset enable debug that wasn't enabled previously in the stack?
    my $debug_previous = $jconfig->{debug};
    my $dump_previous = $jconfig->{dump};

    my $debug = $debug_previous || defined ($Jarvis::Config::yes_value {lc ($dsxml->{dataset}{debug}->content || "no")});
    my $dump = $debug || $debug_previous || defined ($Jarvis::Config::yes_value {lc ($dsxml->{dataset}{dump}->content || "no")});

    # Construct our dataset descriptor.
    my $dataset = {
        level => $level,
        name => $dataset_name,  
        dsxml => $dsxml,
        dbtype => $dbtype,
        dbname => $dbname,
        debug_previous => $debug_previous,
        debug => $debug,
        dump_previous => $dump_previous,
        dump => $dump,        
    };

    # Only the top level set supports paging.
    if ($level == 0) {
        $dataset->{page_start_param} = $axml->{page_start_param}->content || 'page_start';
        $dataset->{page_limit_param} = $axml->{page_limit_param}->content || 'page_limit';
        $dataset->{sort_field_param} = $axml->{sort_field_param}->content || 'sort_field';
        $dataset->{sort_dir_param} = $axml->{sort_dir_param}->content || 'sort_dir';
    }
    push (@{ $jconfig->{datasets}}, $dataset);

    # Change to new debug/dump levels.
    $jconfig->{debug} = $debug;
    $jconfig->{dump} = $dump;

    # We now have one more DS on the stack.
    &Jarvis::Error::debug ($jconfig, "Loaded DSXML for '%s', dataset stack sizes is now %d.", $dataset_name, scalar @{ $jconfig->{datasets} });

    return $dataset;
}

################################################################################
# Unload the top {dataset} from our stack and return debug/dump flags to their
# previous state.
#
# Returns:
#       $dataset - Current stack sized.
################################################################################
#
sub unload_dsxml {
    my ($jconfig) = @_;

    my $dataset = pop (@{ $jconfig->{datasets} });
    &Jarvis::Error::debug ($jconfig, "Unloaded DSXML for '%s', dataset stack sizes is now %d.", $dataset->{name}, scalar @{ $jconfig->{datasets} });

    # Change to previous debug/dump levels.
    $jconfig->{debug} = $dataset->{debug_previous};
    $jconfig->{dump} = $dataset->{dump_previous};

    return scalar @{ $jconfig->{datasets} };
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
    if ($$transforms_href{word2html}) {
        foreach my $key (keys %$vals_href) {
            next if ! defined $$vals_href{$key};
            $$vals_href{$key} = &word2html ($$vals_href{$key});
        }
    }

    # Trim leading and trailing space off any defined value.
    if ($$transforms_href{trim}) {
        foreach my $key (keys %$vals_href) {
            next if ! defined $$vals_href{$key};
            $$vals_href{$key} = &trim ($$vals_href{$key});
        }
    }

    # Convert any whitespace values into undef.  Later, all undef values
    # will be omitted from the final results in JSON and XML format.
    if ($$transforms_href{null}) {
        foreach my $key (keys %$vals_href) {
            next if ! defined $$vals_href{$key};
            if ($$vals_href{$key} =~ m/^\s*$/) {
                $$vals_href{$key} = undef;
            }
        }
    }

    # Any undef values will be converted to whitespace.
    if ($$transforms_href{notnull}) {
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

    $jconfig->{post_data} && return $jconfig->{post_data};

    # Get our submitted content.  This works for POST (insert) on non-XML data.  If the
    # content_type was "application/xml" then I think we will find our content in the
    # 'XForms:Model' parameter instead.
    $jconfig->{post_data} = $jconfig->{cgi}->param ('POSTDATA');

    # This is for POST (insert) on XML data.
    if (! $jconfig->{post_data}) {
        $jconfig->{post_data} = $jconfig->{cgi}->param ('XForms:Model');
    }

    # This works for DELETE (delete) and PUT (update) on any content.
    #
    # PUT/DELETE data appear to come through in a special 'keywords' method.
    # ... unless application/json is used, in which case they have a special
    # PUTDATA param.
    # Weird huh!
    if (! $jconfig->{post_data}) {
        $jconfig->{post_data} = $jconfig->{cgi}->keywords();
    }

    if (! $jconfig->{post_data}) {
        $jconfig->{post_data} = $jconfig->{cgi}->param('PUTDATA');
    }

    # Last ditch effort - read STDIN.
    if (! $jconfig->{post_data}) {
        $jconfig->{post_data} = "";
        while (<STDIN>) {
            $jconfig->{post_data} .= $_;
        }
    }

    return $jconfig->{post_data};
}

################################################################################
# Loads the data for the current dataset(s), and puts it into our return data
# hash so that it can be presented to the client in JSON.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#               format
#                      "json", "json.array", "json.rest", 
#                      "xml",
#                      "csv", "xlsx".
#
#       $dataset_name - Dataset name we parsed/routed to.
#       $rest_args - Hash of numbered and/or named REST args.
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub fetch {
    my ($jconfig, $dataset_name, $rest_args) = @_;
    
    # What format will we encode into.
    my $format = $jconfig->{format};
    
    # Get the data.  Note that this is the very first time in fetch processing
    # that we have performed an EXACT match on the requested format.  Until
    # now, we have only validated the prefix part (e.g. json*, xml*).  Now
    # we will be fussy about the exact requested return format. 
    #
    # Note that we will deal with ".rest" formats a little bit later, for
    # now we just put everything into the normal places.
    #
    if (($format ne 'xml') &&
        ($format ne 'json') && ($format ne 'json.array') && ($format ne 'json.rest') &&
        ($format ne 'csv') && ($format ne 'xlsx')) {
        
        die "No implementation for fetch format '$format', dataset '$dataset_name'.";
    }

    # Get the ROWS inner content for the dataset.
    my ($rows_aref, $column_names_aref) = &fetch_rows ($jconfig, $dataset_name, $rest_args);

    # Now we have an array of hash objects.  Apply post-processing.
    my $num_fetched = scalar @$rows_aref;
    &Jarvis::Error::debug ($jconfig, "Number of rows fetched = $num_fetched (after dataset_fetched hook).");

    # This is for when a router requests a "singleton" presentation explicitly.
    if ($jconfig->{presentation} eq "singleton") {
        if (scalar (@$rows_aref) == 0) {
            $jconfig->{status} = "404 Not Found";
            die "Zero results returned from 'singleton' request.\n";

        } elsif (scalar (@$rows_aref) > 1) {
            $jconfig->{status} = "406 Not Acceptable";
            die "Multiple results returned from 'singleton' request.\n";
        }
    }

    # Invoke the GLOBAL return_fetch hook.
    #
    # This may: Set extra return fields.
    #           Completely override the return content formatting.
    #
    my $extra_href = {};
    my $return_value = undef;
    &Jarvis::Hook::return_fetch ($jconfig, $rest_args, $rows_aref, $extra_href, \$return_value);

    # If the hook performed its own encoding, we have no further work to do.
    if (defined $return_value) {
        &Jarvis::Error::debug ($jconfig, "Return content determined by hook ::return_fetch");

    # XML encoding in its simplest form.  Column keys are attributes.
    } elsif ($format eq "xml") {
        &Jarvis::Error::debug ($jconfig, "Encoding into XML format ($format).");

        my $return_object = XML::Smart->new ();
        $return_object->{data}{row} = $rows_aref;
        $return_object->{response}{logged_in} = $jconfig->{logged_in};
        $return_object->{response}{username} = $jconfig->{username};
        $return_object->{response}{error_string} = $jconfig->{error_string};
        $return_object->{response}{group_list} = $jconfig->{group_list};
        $return_object->{fetched} = 1 * $num_fetched;            # Fetched from database
        $return_object->{returned} = scalar @$rows_aref;         # Returned to client (after paging)

        # Copy across any extra root parameters set by the return_fetch hook.
        foreach my $name (sort (keys %$extra_href)) {
            $return_object->{response}{$name} = $extra_href->{$name};
        }

        $return_value = $return_object->data ();
        
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
        &Jarvis::Error::debug ($jconfig, "Encoding into CSV format ($format).");

        if (! $column_names_aref || ! (scalar @$column_names_aref)) {
            die "Data query did not return column names.  Cannot convert to CSV.";
        }
        
        my %field_index = ();
        @field_index { @$column_names_aref } = (0 .. $#$column_names_aref);

        # Create a string IO handle to print CSV into.
        $return_value = '';
        my $io = IO::String->new ($return_value);

        # Create a CSV object and print the header line.
        my $csv = Text::CSV->new ( { binary => 1 } );
        $csv->print ($io, $column_names_aref);
        print $io "\n";

        # Now print the data.
        foreach my $row (@$rows_aref) {
            my @columns = map { $$row{$_} } @$column_names_aref;
            $csv->print ($io, \@columns);
            print $io "\n";
        }
        
    # XLSX is basically the same as CSV, but with different encoding.
    #
    } elsif ($format eq "xlsx") {
        &Jarvis::Error::debug ($jconfig, "Encoding into XLSX format ($format).");

        # Dynamically load this module.
        require Excel::Writer::XLSX;
        
        if (! $column_names_aref || ! (scalar @$column_names_aref)) {
            die "Data query did not return column names.  Cannot convert to XLSX.";
        }
        
        my %field_index = ();
        @field_index { @$column_names_aref } = (0 .. $#$column_names_aref);

        # Create an IO buffer.
        $return_value = '';
        my $io = IO::String->new ($return_value);

        my $workbook = Excel::Writer::XLSX->new ($io);
        my $size = 10;
        my $default_format = $workbook->add_format (font => 'Arial', size => $size);
        my $worksheet = $workbook->add_worksheet ();
        
        my ($row, $col) = (0, 0);
        foreach my $column_name (@$column_names_aref) {
            $worksheet->write ($row, $col++, $column_name, $default_format);
        }
        $row++;

        foreach my $row (@$rows_aref) {
            $col = 0;
            my @columns = map { $$row{$_} } @$column_names_aref;
            foreach my $value (@columns) {
                $worksheet->write ($row, $col++, $value, $default_format);
            }
            $row++;
        }        
        $workbook->close(); 
        
    # Various JSON formats.
    } elsif (($format eq "json") || ($format eq "json.array") || ($format eq "json.rest")) {

        my $return_object;

        &Jarvis::Error::debug ($jconfig, "Encoding into JSON ($format) format with data as %s.", $jconfig->{presentation});

        # JSON "Restful" encoding is now simple.  It presents ONLY the data.
        if ($format eq "json.rest") {
            if ($jconfig->{presentation} eq "singleton") {
                $return_object = $$rows_aref[0];

            } else {
                $return_object = $rows_aref;
            }
 
        # Other JSON formats have a base object with various attributes.
        } else {    # "json", "json.array"

            # Assemble the result object.
            $return_object = {
                fetched => 1 * $num_fetched,                    # Fetched from database
                returned => scalar @$rows_aref,                 # Returned to client (after paging)
                logged_in => ($jconfig->{logged_in} ? 1 : 0),
                username => $jconfig->{username},
                error_string => $jconfig->{error_string},
                group_list => $jconfig->{group_list},
            };

            # Copy across any extra root parameters set by the return_fetch hook.
            foreach my $name (sort (keys %$extra_href)) {
                $return_object->{$name} = $extra_href->{$name};
            }

            # "json.array"
            if ($format eq "json.array") {

                $return_object->{columns} = $column_names_aref;
                
                # Convert the hashes into rows.
                my @rows2;
                foreach my $row (@$rows_aref) {
                    my @row2 = map { (defined $row->{$_}) ? $row->{$_} : undef } @$column_names_aref;
                    push (@rows2, \@row2);
                }
                $return_object->{data} = \@rows2;

            # "json".
            } else {

                # This is for when a router requests a "singleton" presentation explicitly.
                if ($jconfig->{presentation} eq "singleton") {
                    $return_object->{data} = $$rows_aref[0];

                # This is the default case.  Zero or more objects in an array.
                } else {
                    $return_object->{data} = $rows_aref;
                }
            }
        }

        # Encode into JSON.
        my $json = JSON->new->pretty(1)->allow_blessed(1);
        $return_value = $json->encode ( $return_object );

    # Nothing else supported.
    } else {
        die "No return representation for format '$format', dataset '$dataset_name'.";
    }   

    # Debug/Dump.
    &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($return_value));
    &Jarvis::Error::dump ($jconfig, $return_value) unless ($format eq "xlsx");

    return $return_value;
}


################################################################################
# Performs the inner fetching of a dataset into an ARRAY reference, with no
# formatting.
#
# Params:
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in SQL
#               username            Used for {{username}} in SQL
#               group_list          Used for {{group_list}} in SQL
#
#       $dataset_name - Dataset name we parsed/routed to.
#       $rest_args - Hash of numbered and/or named REST args.
#
# Returns:
#       Reference to Hash of returned data.  You may convert to JSON or XML.
#       die on error (including permissions error)
################################################################################
#
sub fetch_rows {    
    my ($jconfig, $dataset_name, $rest_args) = @_;

    # Turn our CGI params and REST args into a safe list of parameters.
    # This will also add our special parameters - __username, __group_list, etc.
    # It will also merge in application default parameters and session safe variables.
    my $cgi_params = $jconfig->{cgi}->Vars;
    my %params_copy = &Jarvis::Config::safe_variables ($jconfig, $cgi_params, $rest_args, undef);

    # Read the dataset config file.  This changes debug level as a side-effect.
    my $dataset = &load_dsxml ($jconfig, $dataset_name) || die "Cannot load configuration for dataset '$dataset_name'.\n";
    my $dsxml = $dataset->{dsxml};
    my $dbtype = $dataset->{dbtype};
    my $dbname = $dataset->{dbname};

    # Load/Start dataset specific hooks.
    &Jarvis::Hook::load_dataset ($jconfig, $dsxml);

    # Check the allowed groups.
    my $allowed_groups = $dsxml->{dataset}{"read"};

    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{status} = "401 Unauthorized";
        die "Insufficient privileges to read '$dataset_name': $failure\n";
    }    

    # Call the pre-fetch hook.
    my %safe_params = %params_copy;
    &Jarvis::Hook::dataset_pre_fetch ($jconfig, $dsxml, \%safe_params);

    # What filename would this dataset use?
    my $filename_parameter = $dsxml->{dataset}{filename_parameter}->content || 'filename';
    &Jarvis::Error::debug ($jconfig, "Filename parameter = '$filename_parameter'.");        
    $jconfig->{return_filename} = $safe_params {$filename_parameter} || '';        
    &Jarvis::Error::debug ($jconfig, "Return filename = '" . $jconfig->{return_filename} . "'.");        
    
    # Get a database handle.
    my $dbh = &Jarvis::DB::handle ($jconfig, $dbname, $dbtype);

    # Call to the DBI interface to fetch the tuples.
    my ($rows_aref, $column_names_aref);
    
    if ($dbtype eq 'dbi') {
        ($rows_aref, $column_names_aref) 
            = &Jarvis::Dataset::DBI::fetch ($jconfig, $dataset_name, $dsxml, $dbh, \%safe_params);
            
    } elsif ($dbtype eq 'sdp') {
        ($rows_aref, $column_names_aref) 
            = &Jarvis::Dataset::SDP::fetch ($jconfig, $dataset_name, $dsxml, $dbh, \%safe_params);
            
    } else {
        die "Unsupported dataset type '$dbtype'.";
    }
    
    # Do we want to do server side sorting?  This happens BEFORE paging.  Note that this
    # will only work when $sth->{NAME} is available.  Some (all?) stored procedures
    # under MS-SQL Server will not provide field names, and hence this feature will not
    # be available.
    #
    # NOTE: This feature is only provided for the TOP LEVEL dataset.
    #
    if ($dataset->{level} == 0) {
        my $sort_field = $jconfig->{cgi}->param ($dataset->{sort_field_param}) || '';
        my $sort_dir = $jconfig->{cgi}->param ($dataset->{sort_dir_param}) || 'ASC';

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
        my $limit = $jconfig->{cgi}->param ($dataset->{page_limit_param}) || 0;
        my $start = $jconfig->{cgi}->param ($dataset->{page_start_param}) || 0;

        if ($limit > 0) {
            ($start > 0) || ($start = 0); # Check we have a real zero, not ''

            &Jarvis::Error::debug ($jconfig, "Limit = $limit, Offset = $start, Raw Num Rows = %d.", scalar @$rows_aref);

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
    }

    # What transformations should we use when sending out fetch data?
    my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->{dataset}{transform}{fetch});
    &Jarvis::Error::debug ($jconfig, "Fetch transformations = " . join (', ', keys %transforms) . " (applied to returned results)");

    # Apply any output transformations to remaining hashes.
    if (scalar (keys %transforms)) {
        foreach my $row (@$rows_aref) {
            &Jarvis::Dataset::transform (\%transforms, $row);
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
    foreach my $row (@$rows_aref) {
        foreach my $key (keys %$row) {
            (defined $$row{$key}) || delete $$row{$key};
        }
    }            

    # Now do we have any child datasets?
    if ($dsxml->{child}) {
        foreach my $child (@{ $dsxml->{child} }) {

            # What dataset do we use to get child data, and where do we store it?
            $child->{field} || die "Invalid dataset child configuration, <child> with no 'field' attribute.";
            $child->{dataset} || die "Invalid dataset child configuration, <child> with no 'dataset' attribute.";
            my $child_field = $child->{field}->content;
            my $child_dataset = $child->{dataset}->content;
            &Jarvis::Error::debug ($jconfig, "Processing child dataset '$child_dataset' to store as field '$child_field'.");

            # Get all our links.  This ties a parent row value to a child query arg.
            # We can execute with no links, although it doesn't give a very strong parent/child relationship!
            my %links = ();
            if ($child->{link}) {
                foreach my $link (@{ $child->{link} }) {
                    $link->{parent} || die "Invalid dataset child link configuration, <link> with no 'parent' attribute.";
                    $link->{child} || die "Invalid dataset child link configuration, <link> with no 'child' attribute.";
                    $links{$link->{parent}->content} = $link->{child}->content;
                }
            }

            # Now invoke the child dataset for each row.  Really you want to only do this 
            # for single row requests, it could get real inefficient real fast.            
            foreach my $row (@$rows_aref) {

                # Start with a copy of our own rest args.
                my %child_args = %$rest_args;

                # Merge in the row attributes.
                map { $child_args{$_} = $row->{$_} } (keys %$row);

                # Execute the sub query and store it in the child field.
                $row->{$child_field} = &fetch_rows ($jconfig, $child_dataset, \%child_args);
            }
        }
    }    
    
    # This final hook allows you to modify the data returned by SQL for one dataset.
    # This hook may completely modify the returned content (by modifying $rows_aref).
    &Jarvis::Hook::dataset_fetched ($jconfig, $dsxml, \%safe_params, $rows_aref, $column_names_aref);
            
    # In any case, Unload/Finish dataset specific hooks.
    &Jarvis::Hook::unload_dataset ($jconfig);

    # And unwind our own dataset stack.
    &unload_dsxml ($jconfig);

    # And we're done.
    return $rows_aref;
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
#               format - Either 
#                      "json", "json.array", "json.rest", 
#                      "xml",
#                      "csv", "xlsx".
#
#       $dataset_name - Dataset name we parsed/routed to.
#       $rest_args_aref - A ref to our REST args (slash-separated after dataset)
#
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub store {
    my ($jconfig, $dataset_name, $rest_args_aref) = @_;

    # Read the dataset config file.  This changes debug level as a side-effect.
    my $dataset = &load_dsxml ($jconfig, $dataset_name) || die "Cannot load configuration for dataset '$dataset_name'.";
    my $dsxml = $dataset->{dsxml};
    my $dbtype = $dataset->{dbtype};
    my $dbname = $dataset->{dbname};
    
    # Load/Start dataset specific hooks.
    &Jarvis::Hook::load_dataset ($jconfig, $dsxml);

    # Check that we are DBI only.
    ($dbtype eq 'dbi') || die "Datasets of type '$dbtype' do not support store operations.";

    # Now perform security check.
    my $allowed_groups = $dsxml->{dataset}{"write"};
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{status} = "401 Unauthorized";
        die "Insufficient privileges to write '$dataset_name'. $failure\n";
    }
    
    # Get a database handle.
    my $dbh = &Jarvis::DB::handle ($jconfig, $dbname, $dbtype);
    
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
    my $result = &Jarvis::Dataset::DBI::store ($jconfig, $dataset_name, $dsxml, $dbh, $rest_args_aref);

    # In any case, Unload/Finish dataset specific hooks.
    &Jarvis::Hook::unload_dataset ($jconfig);

    # And unwind our own dataset stack.
    &unload_dsxml ($jconfig);

    return $result;
}

1;
