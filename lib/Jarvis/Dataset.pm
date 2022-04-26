###############################################################################
# Description:  Dataset access functions.  This is the core purpose of Jarvis,
#               to provide a front end to your database so that your ExtJS,
#               Adobe Flex, or other web application can have simple JSON or
#               XML web-service access to fetch and update data from your
#               back end SQL database on the server.
#
#               We currently support two different types of datasets:
#
#                   - DBI (via Perl DBI modules and DBD drivers)
#                   - SDP (SSAS DataPump via SOAP and custom codec)
#                   - MongoDB (via Perl MongoDB modules)
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

use Module::Load;
use Data::Dumper;
use JSON;
use URI::Escape;
use Storable qw(dclone);
use Time::HiRes qw (gettimeofday tv_interval);

use XML::LibXML;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;
use Jarvis::Hook;
use Jarvis::Login;

my $AGENT_CLASSES = {
    'dbi' => 'Jarvis::Agent::DBI',
    'sdp' => 'Jarvis::Agent::SDP',
    'mongo' => 'Jarvis::Agent::MongoDB',
};

###############################################################################
# Internal Functions
###############################################################################

################################################################################
# Recurisve helper method that will append new XML LibXML elements to a begining element.
#
#       $return_object - The main XML::LibXML::Document object that we have to append each created node to.
#
#       $parent_node   - The direct parent node that we are attaching the current row against.
#
#       $node_name     - The name of the child node that we are creating.
#
#       $rows          - The data (potentiall nested) that we are appending to the parent node.
#
#       Note: This function may be called recursivly for nested return rows.
#
# Returns:
#       undef
################################################################################
#
sub libxml_append_rows {
    my ($return_object, $parent_node, $node_name, $rows) = @_;

    foreach my $row (@{$rows}) {
        my $child_node = $return_object->createElement ($node_name);

        # Process each key. If a key is a non scalar value then we just set
        # it as an attribute otherwise we create a new child element.
        foreach my $key (keys %{$row}) {
            my $value = $row->{$key};

            # Check for scalars. Nice and easy, just set the attribute.
            if (ref ($value) eq '') {
                $child_node->setAttribute ($key, $value);

            } elsif (ref ($value) eq 'ARRAY') {
                # Recurisve loop processing these items as nested items.
                # The name of the items is derived from the key name.
                libxml_append_rows ($return_object, $child_node, $key, $value);
            }
        }

        $parent_node->addChild ($child_node);
    }
}

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
#           dsxml => $dsxml,        # XML::LibXML object holding config info read from file
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

    ($dataset_name =~ m/^\./) && die "Leading '.' not permitted on dataset name '$dataset_name'\n";
    ($dataset_name =~ m/\.$/) && die "Trailing '.' not permitted on dataset name '$dataset_name'\n";

    # Find the best-matching "dataset_dir" prefix and use that directory.
    my $dsxml_filename = undef;
    my $default_dbtype = undef;
    my $best_prefix_len = -1;
    my $default_dbname = undef;

    # Look at all our 'dataset_dir' entries.  They must all have a directory
    # as their inner content.  Also they may have a type (sdp or dbi), and
    # they can have a prefix which is a "." separated prefix on the incoming
    # dataset.  Note that any remaining "." that aren't stripped off by a prefix
    # match are treated as subdirectories inside the dataset dir.
    #
    my $axml = $jconfig->{xml}->find ('./jarvis/app')->pop ();
    $axml->exists ('./dataset_dir') || die "Missing configuration for mandatory element(s) 'dataset_dir'.\n";

    # Check for duplicate prefixes.
    my %prefix_seen = ();

    foreach my $dsdir ($axml->findnodes ('./dataset_dir')) {

        my $dir = $dsdir->to_literal () || die "Missing directory in 'dataset_dir' element.\n";
        my $type = $dsdir->{type} || 'dbi';
        my $prefix = $dsdir->{prefix} || '';
        my $dbname = $dsdir->{dbname} || 'default';

        # Non-empty prefix paths must end in a "." for matching purposes.
        if ($prefix && ($prefix !~ m/\.$/)) {
            $prefix .= ".";
        }
        my $prefix_len = length ($prefix);

        $prefix_seen{$prefix}++ && die "Duplicate dataset_dir entries for prefix '$prefix' are defined.\n";

        &Jarvis::Error::debug ($jconfig, "Dataset Directory: '$dir', type '$type', prefix '$prefix', dbname '$dbname'.");
        if ($dataset_name =~ m/^$prefix(.*)$/) {
            my $remainder = $1;

            &Jarvis::Error::dump ($jconfig, "Prefix '$prefix' matched, length = " . $prefix_len);
            if ($prefix_len > $best_prefix_len) {
                $best_prefix_len = $prefix_len;
                $default_dbtype = $type;

                # Now turn "." into "/" on the dataset name (with prefix stripped).
                $remainder =~ s/\./\//g;
                $dsxml_filename = "$dir/$remainder.xml";
                $default_dbname = $dbname;
                &Jarvis::Error::debug ($jconfig, "Using dataset directory '$dir', type '$type', default dbname '$dbname'.");
            }
        }
    }
    $dsxml_filename || die "No dataset_dir defined with prefix matching dataset '$dataset_name'.\n";

    # Load the dataset-specific XML file and double-check it has top-level <dataset> tag.
    &Jarvis::Error::debug ($jconfig, "Opening DSXML file '$dsxml_filename', default type '$default_dbtype'.");

    # Check it exists.
    if (! -f $dsxml_filename) {
        $jconfig->{status} = '404 Not Found';
        die "No such DSXML file '$dataset_name.xml' for application '" . $jconfig->{app_name} . "'.\n";
    }

    # Attempt to read our Dataset XML configuration file.
    my $dsxml;
    eval {
        $dsxml = XML::LibXML->load_xml (location => $dsxml_filename);
    };

    # Check for XML::LibXML error object.
    if (ref ($@)) {
        # If we have a specific XML::LibXML::Error object then we can pretty print the error.
        my $error_domain  = $@->domain ();
        my $error_message = $@->message ();
        die "Cannot read '$dsxml_filename': [$error_domain] $error_message\n";

    # Fall back to default error handling.
    } elsif ($@) {
        die "Cannot read '$dsxml_filename': $@.\n";
    }

    ($dsxml->exists ('./dataset')) || die "Missing <dataset> tag in '$dsxml_filename'!\n";

    # What kind of database are we dealing with?
    my $dbname = $dsxml->findvalue ('./dataset/@dbname') || $default_dbname;
    my $dbtype = $dsxml->findvalue ('./dataset/@dbtype') || $default_dbtype;

    # What dataset level are we at in our stack?  Level 0 is the top-level, master dataset.  Others are childs.
    (defined $jconfig->{datasets}) || ($jconfig->{datasets} = []);
    my $level = scalar @{ $jconfig->{datasets} };

    # Does this dataset enable debug that wasn't enabled previously in the stack?
    my $debug_previous = $jconfig->{debug};
    my $dump_previous = $jconfig->{dump};

    my $debug = $debug_previous || defined ($Jarvis::Config::yes_value {lc ($dsxml->findvalue ('./dataset/@debug') || "no")});
    my $dump = $debug || $debug_previous || defined ($Jarvis::Config::yes_value {lc ($dsxml->findvalue ('./dataset/@dump') || "no")});

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
        $dataset->{page_start_param} = $axml->find ('./page_start_param')->to_literal () || 'page_start';
        $dataset->{page_limit_param} = $axml->find ('./page_limit_param')->to_literal () || 'page_limit';
        $dataset->{sort_field_param} = $axml->find ('./sort_field_param')->to_literal () || 'sort_field';
        $dataset->{sort_dir_param}   = $axml->find ('./sort_dir_param')->to_literal ()   || 'sort_dir';
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
# NOTE: We match the first name WHICH IS PRESENT, even if it is UNDEFINED.
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

        # NOTE: Subtle clarification here.
        #
        # We match the first name WHICH IS PRESENT, even if it is UNDEFINED.
        #
        # This is a very subtle change made in order for DBI to be 100% consistent
        # with the MongoDB processing.  Previously we used the first variable that
        # was DEFINED (not just present).
        #
        # In practice, I think these are identical in all real-world cases.
        # So much so that I'm confident enough to make this change.
        #
        foreach my $option (split ('\|', $name)) {

            # The "varname?" syntax is the "exists" mechanism.
            if (($option =~ s/^\?//) || ($option =~ s/\?$//)) {

                # This is simple.  If the row has contains the option then it evaluates to 1, otherwise it evaluates to undef.
                # 
                # NOTE: Using an "exists" test as the non-last element in a pipe-list e.g. "{var1?|var2}" is 
                # pointless since the exists test for "var1?" always terminates the searching process and
                # "var2" is never checked.
                #
                $value = exists ($safe_params_href->{$option}) ? 1 : undef;
                last;

            } else {
                if (exists $safe_params_href->{$option}) {
                    $value = $safe_params_href->{$option};
                    last;
                }
            }
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
    # Our XML from attempting to encode them in base64.
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
# Loads the data for the specified dataset(s), and encodes in JSON, XML, CSV.
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
#       $user_args - Hash of CGI + numbered/named REST args.
#
# Returns:
#       Returning string content in JSON or XML or other format.
#       die on error (including permissions error)
################################################################################
#
sub fetch {
    my ($jconfig, $dataset_name, $user_args) = @_;

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

        die "No implementation for fetch format '$format', dataset '$dataset_name'.\n";
    }

    # Get the ROWS inner content for the dataset.
    my $extra_href = {};
    my $fetch_rows_start = [gettimeofday];
    my ($rows_aref, $column_names_aref) = &fetch_rows ($jconfig, $dataset_name, $user_args, $extra_href);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Fetch Rows in: %fs', tv_interval ($fetch_rows_start));

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
    my $return_value = undef;
    my $return_fetch_start = [gettimeofday];
    &Jarvis::Hook::return_fetch ($jconfig, $user_args, $rows_aref, $extra_href, \$return_value);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Return Fetch Hook in: %fs', tv_interval ($return_fetch_start));

    # If the hook performed its own encoding, we have no further work to do.
    if (defined $return_value) {
        &Jarvis::Error::debug ($jconfig, "Return content determined by hook ::return_fetch");

    # XML encoding in its simplest form.  Column keys are attributes.
    } elsif ($format eq "xml") {
        &Jarvis::Error::debug ($jconfig, "Encoding into XML format ($format).");

        my $return_object = XML::LibXML::Document->new ("1.0", "UTF-8");

        my $response_node = $return_object->createElement ("response");
        $return_object->setDocumentElement ($response_node);

        # Set attributes on the root response object.
        $response_node->setAttribute ("logged_in", $jconfig->{logged_in});
        $response_node->setAttribute ("username", $jconfig->{username});
        $response_node->setAttribute ("error_string", $jconfig->{error_string});
        $response_node->setAttribute ("group_list", $jconfig->{group_list});

        # Create the base element that will contain all of our rows of data.
        my $data_node = $return_object->createElement ("data");
        $response_node->addChild ($data_node);

        # Start off using our "parent" data node, placing the first items into row.
        # Anything else that is nested will use its name for the key.
        libxml_append_rows ($return_object, $data_node, 'row', $rows_aref);

        # Copy across any extra root parameters set by the return_fetch hook.
        foreach my $name (sort (keys %$extra_href)) {
            $response_node->setAttribute ($name, $extra_href->{$name});
        }

        $return_value = $return_object->toString (1);

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

        # Dynamically load this module.
        #
        # NOTE: This is part of the standard Ubuntu distro, but isn't part of
        #       the standard RedHat/CentOS package list.
        #
        require Text::CSV;
        require IO::String;

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
        #
        # NOTE: This is CPAN only, not part of standard Debian or RedHat distros.
        #
        require Excel::Writer::XLSX;
        require IO::String;

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

        my $row_num = 1;
        foreach my $row (@$rows_aref) {
            $col = 0;
            my @columns = map { $$row{$_} } @$column_names_aref;
            foreach my $value (@columns) {
                if (defined $value){
                    # When writing data to the Excel spreadsheet there are a number of limitations.
                    # Issue #13308 we are unable to write encoded URLS longer than 255 characters so we need to check
                    # if that case if occuring useing the same check logic the inferred write function uses.
                    if ($value =~ m/^[fh]tt?ps?:\/\//g && length (uri_escape ($value)) > 255) {
                        # Use the explicit string write function.
                        $worksheet->write_string ($row_num, $col, $value, $default_format);
                    } else {
                        # Use the automatic "magic" writing function.
                        $worksheet->write ($row_num, $col, $value, $default_format);
                    }
                }
                $col ++;
            }
            $row_num++;
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
        die "No return representation for format '$format', dataset '$dataset_name'.\n";
    }

    # Debug/Dump.
    &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($return_value));
    &Jarvis::Error::dump ($jconfig, $return_value) unless ($format eq "xlsx");

    return $return_value;
}


###############################################################################
# DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED
# -- These features are officially documented, remember to
# -- update the documentation if you change/extend then.
###############################################################################
###############################################################################
# Performs the inner fetching of a dataset into an ARRAY reference, with no
# formatting.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dataset_name - Dataset name we parsed/routed to (or child dataset).
#       $user_args - Hash of CGI + numbered/named REST args (top level datasest).
#                    OR linked child args (for nested datasets).
#       $extra_href - Top-level return values we can add to.
#
# Returns:
#       If called in an array context, will return a two element array of:
#           1. Reference to Hash of returned data.
#              You may convert to JSON or XML. die on error
#              (including permissions error)
#           2. A list of column names, if provided by the underlying driver.
#
#       If called in a scalar context, returns only the reference to the hash
#       of returned data.
###############################################################################
#
sub fetch_rows {
    my ($jconfig, $dataset_name, $user_args, $extra_href) = @_;

    &Jarvis::Error::debug ($jconfig, "Fetching dataset rows - load dataset XML and per-datasets hooks.");

    # Plugins using fetch_rows may decide not to give us $user_args or $extra_href;
    (defined $user_args) || ($user_args = {});
    (defined $extra_href) || ($extra_href = {});

    # Timing.
    my $load_dsxml_start = [gettimeofday];

    # Read the dataset config file.  This changes debug level as a side-effect.
    my $dataset = &load_dsxml ($jconfig, $dataset_name) || die "Cannot load configuration for dataset '$dataset_name'.\n";
    my $dsxml = $dataset->{dsxml};
    my $dbtype = $dataset->{dbtype};
    my $dbname = $dataset->{dbname};

    &Jarvis::Error::debug ($jconfig, '[Timing] Loaded DSXML in: %fs', tv_interval ($load_dsxml_start));
    my $load_dataset_start = [gettimeofday];

    # Load/Start dataset specific hooks.
    &Jarvis::Hook::load_dataset ($jconfig, $dsxml);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Load Dataset Hook in: %fs', tv_interval ($load_dataset_start));

    # Check the allowed groups.
    my $allowed_groups = $dsxml->findvalue ('./dataset/@read');

    # Perform CSRF checks.
    Jarvis::Main::check_csrf_protection ($jconfig, $allowed_groups);

    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{status} = "401 Unauthorized";
        die "Insufficient privileges to read '$dataset_name': $failure\n";
    }

    # Get our all-rows safe variables.
    # Turn our CGI params and REST args into a safe list of parameters.
    # This will also add our special parameters - __username, __group_list, etc.
    # It will also merge in application default parameters and session safe variables.
    my %params_copy = &Jarvis::Config::safe_variables ($jconfig, undef, $user_args, undef);

    # Call the pre-fetch hook.
    my %safe_params = %params_copy;
    my $dataset_pre_fetch_start = [gettimeofday];
    &Jarvis::Hook::dataset_pre_fetch ($jconfig, $dsxml, \%safe_params);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Dataset Pre Fetch Hook in: %fs', tv_interval ($dataset_pre_fetch_start));

    # Get a database handle.
    my $dbh = undef;
    my $get_handle_start = [gettimeofday];
    if ($dataset->{level} == 0) {
        &Jarvis::Error::debug ($jconfig, "Top-Level Fetch Dataset.  Opening database handle.");
        $dbh = &Jarvis::DB::handle ($jconfig, $dbname, $dbtype);
        $jconfig->{txn_dbh} = $dbh;

    } elsif ($jconfig->{txn_dbh}) {
        &Jarvis::Error::debug ($jconfig, "Nested Fetch Dataset.  Existing database handle. Using already-open parent database handle.");
        $dbh = $jconfig->{txn_dbh};
    } else {
        &Jarvis::Error::debug ($jconfig, "Nested Fetch Dataset.  Opening database handle.");
        $dbh = &Jarvis::DB::handle ($jconfig, $dbname, $dbtype);
        $jconfig->{txn_dbh} = $dbh;
    }

    &Jarvis::Error::debug ($jconfig, '[Timing] Got Database Handle in: %fs', tv_interval ($get_handle_start));

    # Load the agent class (at the top level only).
    if ($dataset->{level} == 0) {
        $jconfig->{agent_class} = $AGENT_CLASSES->{$dbtype} // die "Unsupported DB Type '$dbtype'.";
        load $jconfig->{agent_class};
    }
    my $agent_class = $jconfig->{agent_class};

    # Now fetch the tuples.
    my $fetch_innert_start = [gettimeofday];
    my ($rows_aref, $column_names_aref);
    {
        no strict 'refs';
        ($rows_aref, $column_names_aref) = $agent_class->fetch_inner ($jconfig, $dataset_name, $dsxml, $dbh, \%safe_params);
    }

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Fetch Inner in: %fs', tv_interval ($fetch_innert_start));

    # Now we have an array of hash objects.  Apply post-processing.
    my $num_fetched = scalar @$rows_aref;
    $extra_href->{fetched} = $num_fetched;

    &Jarvis::Error::debug ($jconfig, "Fetch Result:");
    &Jarvis::Error::debug_var ($jconfig, $rows_aref);
    &Jarvis::Error::debug ($jconfig, "Number of rows fetched = $num_fetched.");

    # Do we want to do server side sorting?  This happens BEFORE paging.  Note that this
    # will only work when $sth->{NAME} is available.  Some (all?) stored procedures
    # under MS-SQL Server will not provide field names, and hence this feature will not
    # be available.
    #
    # NOTE: This feature is only provided for the TOP LEVEL dataset.
    #
    if ($dataset->{level} == 0) {
        my $sort_field = $user_args->{$dataset->{sort_field_param}} || '';
        my $sort_dir = $user_args->{$dataset->{sort_dir_param}} || 'ASC';

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
        my $limit = $user_args->{$dataset->{page_limit_param}} || 0;
        my $start = $user_args->{$dataset->{page_start_param}} || 0;

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
    my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->findvalue ('./dataset/transform/@fetch'));
    &Jarvis::Error::debug ($jconfig, "Fetch transformations = " . join (', ', keys %transforms) . " (applied to returned results)");

    # Apply any output transformations to remaining hashes.
    if (scalar (keys %transforms)) {
        foreach my $row (@$rows_aref) {
            &Jarvis::Dataset::transform (\%transforms, $row);
        }
    }

    &Jarvis::Error::debug ($jconfig, "Fetch Result (after transformations):");
    &Jarvis::Error::debug_var ($jconfig, $rows_aref);

    ###########################################################################
    # DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED
    # -- These features are officially documented, remember to
    # -- update the documentation if you change/extend then.
    ###########################################################################
    #
    # If the retain null flag has been set then we do not want to remove undef values from the return array.
    # This will allow us to have null values in our JSON object.
    #
    if (! $jconfig->{'retain_null'}) {
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
    }

    # Now do we have any child datasets?
    if ($dsxml->exists ('./dataset/child')) {
        &Jarvis::Error::debug ($jconfig, "We have child datasets to append.");

        foreach my $child ($dsxml->findnodes ('./dataset/child')) {

            # What dataset do we use to get child data, and where do we store it?
            $child->{field} || die "Invalid dataset child configuration, <child> with no 'field' attribute.\n";
            $child->{dataset} || die "Invalid dataset child configuration, <child> with no 'dataset' attribute.\n";
            my $child_field = $child->{field};
            my $child_dataset = $child->{dataset};
            &Jarvis::Error::debug ($jconfig, "Processing child dataset '$child_dataset' to store as field '$child_field'.");

            # Get all our links.  This ties a parent row value to a child query arg.
            # We can execute with no links, although it doesn't give a very strong parent/child relationship!
            my %links = ();
            if ($child->exists ('./link')) {
                foreach my $link ($child->findnodes ('./link')) {
                    $link->{parent} || die "Invalid dataset child link configuration, <link> with no 'parent' attribute.\n";
                    $link->{child} || die "Invalid dataset child link configuration, <link> with no 'child' attribute.\n";
                    $links{$link->{parent}} = $link->{child};
                }
            }

            # Now invoke the child dataset for each row.  Really you want to only do this
            # for single row requests, it could get real inefficient real fast.
            foreach my $row (@$rows_aref) {

                # We copy across only the child args.
                my %child_args = ();
                foreach my $parent (keys %links) {
                    my $child = $links{$parent};
                    $child_args{$child} = $row->{$parent};
                    &Jarvis::Error::debug ($jconfig, "Passing FETCHED parent field [%s] -> child field [%s] as value '%s'.", $parent, $child, $child_args{$child});
                }

                # Change debug output to show the nested set.
                my $old_dataset_name = $jconfig->{dataset_name};
                $jconfig->{dataset_name} .= ">" . $child_dataset;

                # Execute the sub query and store it in the child field.
                # This will add default and safe args.
                my $fetch_child_rows_start = [gettimeofday];
                $row->{$child_field} = &fetch_rows ($jconfig, $child_dataset, \%child_args, $extra_href);
                &Jarvis::Error::debug ($jconfig, '[Timing] Completed Fetch Child Rows in: %fs', tv_interval ($fetch_child_rows_start));

                # Restore the old name for debugging.
                $jconfig->{dataset_name} = $old_dataset_name;
            }
        }
    }

    # What filename would this dataset use?  This is an ugly side-effect.
    #
    # TODO: Get rid of this parameter from the dataset/exec/plugin level.
    #       See http://support.nsquaredsoftware.com/tickets/view.php?id=6777
    #
    if ($dataset->{level} == 0) {
        my $filename_parameter = $dsxml->findvalue ('./dataset/@filename_parameter') || 'filename';
        &Jarvis::Error::debug ($jconfig, "Filename parameter = '$filename_parameter'.");
        $jconfig->{return_filename} = $safe_params {$filename_parameter} || '';
        &Jarvis::Error::debug ($jconfig, "Return filename = '" . $jconfig->{return_filename} . "'.");
    }

    # This final hook allows you to modify the data returned by SQL for one dataset.
    # This hook may completely modify the returned content (by modifying $rows_aref).
    my $dataset_fetched_start = [gettimeofday];
    &Jarvis::Hook::dataset_fetched ($jconfig, $dsxml, \%safe_params, $rows_aref, $extra_href, $column_names_aref);
    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Dataset Fetched Hook in: %fs', tv_interval ($dataset_fetched_start));

    # Now we have an array of hash objects.  Apply post-processing.
    my $num_returned = scalar @$rows_aref;
    &Jarvis::Error::debug ($jconfig, "Number of rows returned = $num_returned (after 'dataset_fetched' hook).");
    $extra_href->{returned} = 1 * $num_returned;

    # In any case, Unload/Finish dataset specific hooks.
    my $unload_dataset_start = [gettimeofday];
    &Jarvis::Hook::unload_dataset ($jconfig);
    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Unload Dataset Hook in: %fs', tv_interval ($unload_dataset_start));

    # And unwind our own dataset stack.
    &unload_dsxml ($jconfig);

    # And we're done.
    return wantarray ? ($rows_aref, $column_names_aref) : $rows_aref;
}

################################################################################
# Performs top-level update.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dataset_name - Dataset name we parsed/routed to.
#       $user_args - Hash of CGI + numbered/named REST args.
#
# Returns:
#       "OK" on succes
#       "Error message" on soft error (duplicate key, etc.).
#       die on hard error.
################################################################################
#
sub store {
    my ($jconfig, $dataset_name, $user_args) = @_;

    # NOTE: The return format is implied by the input format.
    my $format = undef;

    # ARRAY ref of per-row fields HASH we need to store.
    my $rows_aref = undef;

    # Check we have some changes and parse 'em from the JSON.  We get an
    # array of hashes.  Each array entry is a change record.
    my $return_array = 0;

    # Get our submitted content
    my $content = &Jarvis::Dataset::get_post_data ($jconfig);
    &Jarvis::Error::debug ($jconfig, "Request Content Length = " . length ($content));
    &Jarvis::Error::dump ($jconfig, $content);

    # Dig into the CGI to get the top-level of the data structure.
    my $content_type = $jconfig->{cgi}->content_type () || '';
    &Jarvis::Error::debug ($jconfig, "Request Content Type = '" . $content_type . "'");

    if ($content_type =~ m|^[a-z]+/json(;.*)?$|) {
        $format = 'json';
        my $ref = JSON->new->utf8->decode ($content);

        # User may pass a single hash record, OR an array of hash records.  We normalise
        # to always be an array of hashes.
        if (ref $ref eq 'HASH') {
            $rows_aref = [ $ref ];

        } elsif (ref $ref eq 'ARRAY') {
            $return_array = 1;
            $rows_aref = $ref;

        } else {
            die "Bad JSON ref type " . (ref $ref);
        }

    # XML in here please.
    } elsif ($content_type =~ m|^[a-z]+/xml(;.*)?$|) {
        $format = 'xml';

        # Parse the content input string into an XML::LibXMl document.
        my $cxml = XML::LibXML->load_xml (
            string => $content
        );

        # Sanity check on outer object.
        $cxml->exists ('./request') || die "Missing top-level 'request' element in submitted XML content.\n";

        # Fields may either sit at the top level, or you may provide an array of
        # records in a <row> array.
        #
        my @rows = ();
        if ($cxml->exists ('./request/row')) {
            foreach my $cxml_row ($cxml->findnodes ('./request/row')) {
                # Data can be store in either an attribute or an element. We need to parse both types.
                my %fields;

                # Process /* this will get all of our elements.
                map { $fields{$_->nodeName} = $_->to_literal } $cxml_row->findnodes ('./*');

                # Then perform @* which is all of our attributes.
                map { $fields{$_->nodeName} = $_->nodeValue } $cxml_row->findnodes ('./@*');

                push (@rows, \%fields);
            }
            $return_array = 1;

        } else {
            # Process each of the arguments stored on the request object. Same deal as with the row object. Might be elements or attributes.
            my %fields;

            # Again process all elements underneath the request element.
            map { $fields{$_->nodeName} = $_->to_literal } $cxml->findnodes ('./request/*');

            # Afterwards again process each attribute underneath the request element.
            map { $fields{$_->nodeName} = $_->nodeValue } $cxml->findnodes ('./request/@*');

            push (@rows, \%fields);
        }
        $rows_aref = \@rows;

    # No body.  Execute a Single-Row with rest-args/cgi-args only.
    } else {
        &Jarvis::Error::debug ($jconfig, "No content supplied.  Store a single empty row + REST/CGI args.");
        $rows_aref = [{}];
    }

    # What is the default transaction type from here down?
    my $ttype = $jconfig->{action};
    &Jarvis::Error::debug ($jconfig, "Transaction Type = '$ttype'");
    ($ttype eq "delete") || ($ttype eq "update") || ($ttype eq "insert") || ($ttype eq "mixed") || ($ttype eq "merge") ||
        die "Unsupported transaction type '$ttype'.\n";

    # Store the row content for the top-level dataset.  This may push out to child sets.
    my $extra_href = {};
    my $store_rows_start = [gettimeofday];
    my ($success, $message, $modified, $results_aref) = &store_rows ($jconfig, $dataset_name, $ttype, $user_args, $rows_aref, $extra_href);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Store Rows in: %fs', tv_interval ($store_rows_start));

    # This final GLOBAL hook allows you to do whatever you want to modify the returned
    # data.  This hook may do one or both of:
    #
    #   - Completely modify the returned content (by modifying \@results)
    #   - Peform a custom encoding into text (by setting $return_text)
    #
    my $return_text = undef;
    my $return_store_start = [gettimeofday];
    &Jarvis::Hook::return_store ($jconfig, $user_args, $results_aref, $extra_href, \$return_text);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Return Store Hook in: %fs', tv_interval ($return_store_start));

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
    } elsif ($jconfig->{format} =~ m/^json/) {
        &Jarvis::Error::debug ($jconfig, "Returning JSON.  Return Array = $return_array.");

        my $return_object = {};
        $return_object->{success} = $success;
        $return_object->{logged_in} = $jconfig->{logged_in};
        $return_object->{username} = $jconfig->{username};
        $return_object->{error_string} = $jconfig->{error_string};
        $return_object->{group_list} = $jconfig->{group_list};
        $success && ($return_object->{modified} = $modified);
        $success || ($return_object->{message} = &trim($message));
        foreach my $name (sort (keys %$extra_href)) {
            $return_object->{$name} = $extra_href->{$name};
        }

        # Return the array data if we succeded.
        if ($success && $return_array) {
            $return_object->{row} = $results_aref;
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            $$results_aref[0]{returning} && ($return_object->{returning} = $$results_aref[0]{returning});
        }
        my $json = JSON->new->pretty(1);
        $return_text = $json->encode ($return_object);

    } elsif ($jconfig->{format} eq "xml") {
        &Jarvis::Error::debug ($jconfig, "Returning XML.  Return Array = $return_array.");

        # Construct our LibXML core document.
        my $return_object = XML::LibXML::Document->new ("1.0", "UTF-8");

        # Create and append the response node as required.
        my $response_node = $return_object->createElement ("response");
        $return_object->setDocumentElement ($response_node);

        # Set our reponse object attributes as required.
        $response_node->setAttribute ('success', $success);
        $response_node->setAttribute ('logged_in', $jconfig->{logged_in});
        $response_node->setAttribute ('username', $jconfig->{username});
        $response_node->setAttribute ('error_string', $jconfig->{error_string});
        $response_node->setAttribute ('group_list', $jconfig->{group_list});

        # Set modified and message attributes depending on our success state.
        $success && ($response_node->setAttribute ('modified', $modified));
        $success || ($response_node->setAttribute ('message', &trim($message)));

        # Process extra parameters. These are all stored as attributes as well.
        foreach my $name (sort (keys %$extra_href)) {
            $response_node->setAttribute ($name, $extra_href->{$name});
        }

        # Return the array data if we succeeded. We encode a results object and encode rows for each entry in our results AREF.
        if ($success && $return_array) {

            # Create top level results.
            my $results_node = $return_object->createElement ("results");
            $response_node->addChild ($results_node);

            # Start off using our "parent" result node, placing the first items into row.
            # Anything else that is nested will use its name for the key.
            libxml_append_rows ($return_object, $results_node, 'row', $results_aref);
        }

        # Return non-array fields in success case only.
        if ($success && ! $return_array) {
            if ($$results_aref[0]{returning}) {
                # Append the single returning object into a returning array underneath our top level response node.
                libxml_append_rows ($return_object, $response_node, 'returning', $$results_aref[0]{returning});
            }
        }

        # Output the return test using the to string method. Providing 1 to auto indent the text.
        $return_text = $return_object->toString (1);

    } else {
        die "Unsupported format '" . $jconfig->{format} ."' for Dataset::store return data.\n";
    }

    &Jarvis::Error::debug ($jconfig, "Returned content length = " . length ($return_text));
    &Jarvis::Error::dump ($jconfig, $return_text);

    return $return_text;
}

################################################################################
# DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED DOCUMENTED
# -- These features are officially documented, remember to
# -- update the documentation if you change/extend then.
################################################################################
################################################################################
# Performs an update to the specified table underlying the named dataset.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dataset_name - Dataset name we parsed/routed to (or child dataset).
#       $ttype - Default transaction type from here down.
#       $user_args - Hash of CGI + numbered/named REST args (top level datasest).
#                    OR linked child args (for nested datasets).
#       $rows_aref - Array of records to store.
#       $extra_href - Top-level return values we can add to.
#
# Returns:
#       ($success, $message, $modified, $results_aref)
#           $success - 1/0 did all inserts fail.
#           $message - "Error message" on soft error (duplicate key, etc.).
#           $modified - Number of top-level rows modified.
#           $results_aref - Returned results, one per row, potentially nested.
#
#       die on hard error.
################################################################################
#
sub store_rows {
    my ($jconfig, $dataset_name, $ttype, $user_args, $rows_aref, $extra_href) = @_;

    # Timing.
    my $load_dsxml_start = [gettimeofday];

    # Read the dataset config file.  This changes debug level as a side-effect.
    my $dataset = &load_dsxml ($jconfig, $dataset_name) || die "Cannot load configuration for dataset '$dataset_name'.\n";
    my $dsxml = $dataset->{dsxml};
    my $dbtype = $dataset->{dbtype};
    my $dbname = $dataset->{dbname};

    &Jarvis::Error::debug ($jconfig, '[Timing] Loaded DSXML in: %fs', tv_interval ($load_dsxml_start));
    my $load_dataset_start = [gettimeofday];

    # Load/Start dataset specific hooks.
    &Jarvis::Hook::load_dataset ($jconfig, $dsxml);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Load Dataset Hook in: %fs', tv_interval ($load_dataset_start));

    # Now perform security check.
    my $allowed_groups = $dsxml->findvalue ('./dataset/@write');
    my $failure = &Jarvis::Login::check_access ($jconfig, $allowed_groups);
    if ($failure ne '') {
        $jconfig->{status} = "401 Unauthorized";
        die "Insufficient privileges to write '$dataset_name'. $failure\n";
    }

    # We pre-compute the "before" statement parameters even if there is
    # no before statement, since we may also wish to record them for later.
    #
    # Merge CGI params + REST args, plus default, safe and session vars.
    #
    my %safe_all_rows_params = &Jarvis::Config::safe_variables ($jconfig, undef, $user_args, undef);

    # What transforms should we use when processing store data?
    my %transforms = map { lc (&trim($_)) => 1 } split (',', $dsxml->findvalue ('./dataset/transform/@store'));
    &Jarvis::Error::debug ($jconfig, "Store transformations = " . join (', ', keys %transforms) . " (applied to incoming row data)");

    # Apply input transformations to the all-rows before_all/after_all parameters too.`
    if (scalar (keys %transforms)) {
        &Jarvis::Dataset::transform (\%transforms, \%safe_all_rows_params);
    }

    # Call the pre-store hook.
    my $dataset_pre_store_start = [gettimeofday];
    &Jarvis::Hook::dataset_pre_store ($jconfig, $dsxml, \%safe_all_rows_params, $rows_aref);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Dataset Pre Store Hook in: %fs', tv_interval ($dataset_pre_store_start));

    # Load the agent class (at the top level only).
    if ($dataset->{level} == 0) {
        $jconfig->{agent_class} = $AGENT_CLASSES->{$dbtype} // die "Unsupported DB Type '$dbtype'.";
        load $jconfig->{agent_class};
    }
    my $agent_class = $jconfig->{agent_class};

    # Get a database handle.
    my $dbh = undef;
    if ($dataset->{level} == 0) {
        no strict 'refs';

        &Jarvis::Error::debug ($jconfig, "Top-Level Store Dataset.  Opening database handle.");
        $dbh = &Jarvis::DB::handle ($jconfig, $dbname, $dbtype);
        $jconfig->{txn_dbh} = $dbh;

        # Start a transaction (if our agent supports it).
        $agent_class->transaction_begin ($jconfig, $dbh);

    } else {
        &Jarvis::Error::debug ($jconfig, "Nested Store Dataset.  Using already-open parent database handle.");
        $dbh = $jconfig->{txn_dbh};
    }

    # Invoke before_all hook. Deep clone our safe parameters here as any changes should only affect our before SQL.
    my $before_params = dclone (\%safe_all_rows_params);
    my $before_all_start = [gettimeofday];
    &Jarvis::Hook::before_all ($jconfig, $dsxml, $before_params, $rows_aref);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Before All Hook in: %fs', tv_interval ($before_all_start));

    # Loop for each set of updates.
    my $success = 1;
    my $modified = 0;
    my $results_aref = [];
    my $message = '';

    # Execute our "before" statement (assuming the agent supports it).
    if ($dsxml->exists ('./dataset/before')) {
        no strict 'refs';
        my $execute_before_start = [gettimeofday];
        my $result = $agent_class->execute_before ($jconfig, $dataset_name, $dsxml, $dbh, $before_params);
        if (defined $result) {
            $success = 0;
            $message = $result;
        }

        &Jarvis::Error::debug ($jconfig, '[Timing] Completed Execute Before Statement in: %fs', tv_interval ($execute_before_start));
    }

    # Our cached statement handle(s).
    my $stms = {};

    # Handle each insert/update/delete request row.
    foreach my $fields_href (@$rows_aref) {

        ((ref $fields_href) eq 'HASH') || die "User-supplied object to store is not HASH.";

        # Re-do our parameter merge, this time including our per-row parameters.
        my %safe_params = &Jarvis::Config::safe_variables ($jconfig, \%safe_all_rows_params, $user_args, $fields_href);

        # Any input transformations?
        if (scalar (keys %transforms)) {
            &Jarvis::Dataset::transform (\%transforms, \%safe_params);
        }

        # Invoke before_one hook.
        my $before_one_start = [gettimeofday];
        &Jarvis::Hook::before_one ($jconfig, $dsxml, \%safe_params);

        &Jarvis::Error::debug ($jconfig, '[Timing] Completed Before One Hook in: %fs', tv_interval ($before_one_start));

        # Figure out which statement type we will use for this row.
        my $row_ttype = $safe_params{_ttype} || $ttype;
        ($row_ttype eq 'mixed') && die "Transaction Type 'mixed', but no '_ttype' field present in row.\n";

        # Hand off to agent for the actual store (assuming it supports it).
        # This also perform our "returning" logic (if applicable).
        my $row_result = undef;
        my $store_inner_start = [gettimeofday];
        {
            no strict 'refs';
            $row_result = $agent_class->store_inner ($jconfig, $dataset_name, $dsxml, $dbh, $stms, $row_ttype, \%safe_params, $fields_href);
        }
        &Jarvis::Error::debug ($jconfig, '[Timing] Completed Store Inner in: %fs', tv_interval ($store_inner_start));

        # Increment our top-level counts.
        $modified = $modified + $row_result->{modified};
        if (! $row_result->{success}) {
            $success = 0;
            $message = $row_result->{message};

            # This is DBD::Sybase string cleanup.
            $message =~ s/^Server message number=[0-9]+ severity=[0-9]+ state=[0-9]+ line=[0-9]+ server=[A-Z0-9\\]+text=//i;
        }

        # Store the results, even if they are not successful.
        push (@$results_aref, $row_result);

        # Stop as soon as anything goes wrong.
        if (! $success) {
            &Jarvis::Error::debug ($jconfig, "Error detected.  Stopping.");
            last;
        }

        # Now do we have any child datasets?
        if ($dsxml->exists ('./dataset/child')) {

            # For insert/update only!  Don't recurse on delete.
            if ($row_ttype eq 'delete') {
                &Jarvis::Error::debug ($jconfig, "Ignoring child datasets for '$row_ttype' store.");

            } else {
                &Jarvis::Error::debug ($jconfig, "Processing child datasets for '$row_ttype' store.");
            }
            foreach my $child ($dsxml->findnodes ('./dataset/child')) {

                # What dataset do we use to get child data, and where do we store it?
                $child->{field} || die "Invalid dataset child configuration, <child> with no 'field' attribute.\n";
                $child->{dataset} || die "Invalid dataset child configuration, <child> with no 'dataset' attribute.\n";
                my $child_field = $child->{field};
                my $child_dataset = $child->{dataset};
                &Jarvis::Error::debug ($jconfig, "Processing child dataset '$child_dataset' to store as field '$child_field'.");

                # Get all our links.  This ties a parent row value to a child query arg.
                # We can execute with no links, although it doesn't give a very strong parent/child relationship!
                my %links = ();
                if ($child->exists ('./link')) {
                    foreach my $link ($child->findnodes ('./link')) {
                        $link->{parent} || die "Invalid dataset child link configuration, <link> with no 'parent' attribute.\n";
                        $link->{child} || die "Invalid dataset child link configuration, <link> with no 'child' attribute.\n";
                        $links{$link->{parent}} = $link->{child};
                    }
                }

                # Right, we will only continue now if we have been provided with rows to action.
                my $child_rows_aref = $fields_href->{$child_field};
                if (! defined $child_rows_aref) {
                    &Jarvis::Error::debug ($jconfig, "No supplied rows for '$child_field' in parent.  Skip child dataset.");
                    next;
                }
                ((ref $child_rows_aref) eq 'ARRAY') || die "Parent dataset has child dataset field '$child_field' but it is not ARRAY.\n";

                # Parent/Child links will be passed through from SUPPLIED and RETURNING parameters too.
                my %child_args = ();
                foreach my $parent (keys %links) {
                    my $child = $links{$parent};

                    # Returning parameters take precedence.  Note that in theory a "returning"
                    # clause can return more than one row.  But we only ever use the first returned row.
                    if ($row_result->{returning} && (scalar @{ $row_result->{returning} }) && exists $row_result->{returning}[0]->{$parent}) {
                        $child_args{$child} = $row_result->{returning}[0]->{$parent};
                        &Jarvis::Error::debug ($jconfig, "Passing RETURNING parent field [%s] -> child field [%s] as value '%s'.", $parent, $child, $child_args{$child});

                    } else {
                        $child_args{$child} = $fields_href->{$parent};
                        &Jarvis::Error::debug ($jconfig, "Passing SUPPLIED parent field [%s] -> child field [%s] as value '%s'.", $parent, $child, $child_args{$child});
                    }
                }

                # Change debug output to show the nested set.
                my $old_dataset_name = $jconfig->{dataset_name};
                $jconfig->{dataset_name} .= ">" . $child_dataset;

                # Execute the sub query and store it in the child field.
                # This will add default and safe args.
                my $store_child_rows_start = [gettimeofday];
                my ($child_success, $child_message, $child_modified, $child_results_aref) =
                    &store_rows ($jconfig, $child_dataset, $row_ttype, \%child_args, $child_rows_aref, $extra_href);

                &Jarvis::Error::debug ($jconfig, '[Timing] Completed Store Child Rows in: %fs', tv_interval ($store_child_rows_start));

                # Restore the old name for debugging.
                $jconfig->{dataset_name} = $old_dataset_name;

                # Failure?  Pass back up.
                if (! $child_success) {
                    &Jarvis::Error::debug ($jconfig, "Child dataset store failed.  Abandon nested store.");
                    $success = 0;
                    $message = $child_message;
                    last;
                }

                # Success?
                $row_result->{child}{$child_field} = {
                    success => $child_success,
                    modified => $child_modified,
                    row => $child_results_aref,
                }
            }
        }

        # Stop on child dataset problem.
        if (! $success) {
            &Jarvis::Error::debug ($jconfig, "Error detected in child dataset.  Stopping.");
            last;
        }

        # Call the after_one hook ONLY on success, and after child datasets are processed.
        my $after_one_start = [gettimeofday];
        &Jarvis::Hook::after_one ($jconfig, $dsxml, \%safe_params, $row_result);

        &Jarvis::Error::debug ($jconfig, '[Timing] Completed After One Hook in: %fs', tv_interval ($after_one_start));
    }

    # Free any remaining open statement types.
    {
        no strict 'refs';
        $agent_class->free_statements ($jconfig, $dbh, $stms);
    }

    # Execute our "after" statement.
    # As of 6.1.0 this (and the after_all hook) occurs INSIDE the transaction.
    if ($success) {

        # Reset our parameters, our per-row parameters are no longer valid.
        my %after_params = %safe_all_rows_params;

        # Execute our "after" statement (assuming the agent supports it).
        if ($dsxml->exists ('./dataset/after')) {
            no strict 'refs';
            my $execute_after_start = [gettimeofday];;
            my $result = $agent_class->execute_after ($jconfig, $dataset_name, $dsxml, $dbh, \%after_params);
            if (defined $result) {
                $success = 0;
                $message = $result;
            }

            &Jarvis::Error::debug ($jconfig, '[Timing] Completed Execute After Hook in: %fs', tv_interval ($execute_after_start));
        }

        # Invoke the "after_all" hook, if the "after" statement succeeded.
        # Or even if we have no "after" statement.
        if ($success) {
            my $after_all_start = [gettimeofday];
            &Jarvis::Hook::after_all ($jconfig, $dsxml, \%after_params, $rows_aref, $results_aref);

            &Jarvis::Error::debug ($jconfig, '[Timing] Completed After All Hook in: %fs', tv_interval ($after_all_start));
        }
    }

    # Determine if we're going to rollback.
    # This now occurs subsequent to the "after" statement and hook.
    if ($dataset->{level} == 0) {
        no strict 'refs';

        if (! $success) {
            &Jarvis::Error::debug ($jconfig, "Store Error detected.  Rolling back (if supported).");
            $agent_class->transaction_rollback ($jconfig, $dbh);

        } else {
            &Jarvis::Error::debug ($jconfig, "Store all successful.  Committing all changes (if supported).");
            $agent_class->transaction_commit ($jconfig, $dbh);
        }
    }

    # This final hook allows you to modify the data returned for one dataset.
    # This hook may completely modify the returned content (by modifying $rows_aref).
    #
    # NOTE: This is called even on non-success.
    my $dataset_stored_start = [gettimeofday];
    &Jarvis::Hook::dataset_stored ($jconfig, $dsxml, \%safe_all_rows_params, $results_aref, $extra_href, \$success, \$message);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Dataset Stored Hook in: %fs', tv_interval ($dataset_stored_start));

    # In any case, Unload/Finish dataset specific hooks.
    my $unload_dataset_start = [gettimeofday];
    &Jarvis::Hook::unload_dataset ($jconfig);

    &Jarvis::Error::debug ($jconfig, '[Timing] Completed Unload Dataset Hook in: %fs', tv_interval ($unload_dataset_start));

    # And unwind our own dataset stack.
    &unload_dsxml ($jconfig);

    return ($success, $message, $modified, $results_aref);
}

1;
