###############################################################################
# Description:  Dataset access functions for SSAS DataPump access.
#
#               A SDP dataset is defined by a <dataset>.xml file which contains
#               a single MDX query.
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

use JSON::PP;           # JSON::PP was giving double-free/corruption errors.
use XML::Smart;
use Text::CSV;
use IO::String;

package Jarvis::Dataset::SDP;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;
use Jarvis::Hook;

use sort 'stable';      # Don't mix up records when server-side sorting

################################################################################
# Expand the MDX:
#       - Replace {$args} with text equivalent.
#       - Replace [$args] with text equivalent.
#
# Note that the SQL/DBI version allows more flexible syntax.  We do not, we 
# support only the single specified formats.  In the future we will be forcing
# DBI datasets to move to the same syntax.
#
# See: http://msdn.microsoft.com/en-us/library/ms145572(v=sql.90).aspx
#
# Params:
#       $jconfig - Jarvis config object.
#       $mdx - MDX text.
#       $args_href - Hash of Fetch and REST args.
#
# Returns:
#       ($mdx_with_substitutions, @variable_names).
################################################################################
#
sub mdx_with_substitutions {

    my ($jconfig, $mdx, $args_href) = @_;

    # Parameters NAMES may contain only a-z, A-Z, 0-9, underscore(_), colon(:) and hyphen(-)
    # Note pipe(|) is also allowed at this point as it separates (try-else variable names)
    #
    my @bits = split (/\{\$([a-zA-Z0-9_\-:\|]+)\}/i, $mdx);

    my $mdx2 = "";
    foreach my $idx (0 .. $#bits) {
        if ($idx % 2) {
            my $name = $bits[$idx];
            my %flags = ();

            # Flags may be specified after the variable name with a colon separating the variable
            # name and the flag.  Multiple flags are permitted in theory, with a colon before
            # each flag.  Supported flags at this stage are:
            #
            #   <none> - Allow only specific safe characters.
            #   :string - Escape suitable for use in StrToMbr(" ")
            #   :bracket - Use ]] for ].  Allow most others.
            #
            # Note, I sat for quite a while here wondering if we should make the
            # system a bit "smarter", i.e. allow it to examine the surrounding
            # context for each value to determine if e.g. it was preceded by an
            # open bracket, and we should automatically activate the :bracket
            # flag.  But in the end, I just couldn't see that it was going to be
            # 100% safe or reliable.  So let's leave it in the query designer's
            # hands, and just default to "safe" mode. 
            #
            while ($name =~ m/^(.*)\:([^\:]+)$/) {
                $name = $1;
                my $flag = lc ($2);
                $flag =~ s/[^a-z]//g;
                $flags {$flag} = 1;
            }

            # The name may be a pipe-separated sequence of "names to try".
            my $value = undef;
            foreach my $option (split ('\|', $name)) {
                $value = $args_href->{$option};
                last if (defined $value);
            }
            (defined $value) || ($value = '');

            # With the :string flag, or if the preceding character was a string, 
            # then escape for use in StrToMbr(" ")
            if ($flags{'string'}) {
                $value =~ s/\\/\\\\/g;
                $value =~ s/"/\\"/g;
                $mdx2 .= $value;
                
            # We can allow brackets. 
            } elsif ($flags{'bracket'}) {
                $value =~ s/\]/\]\]/g;
                $mdx2 .= $value;
                
            # Or else we will just use plain identifiers.  Characters and spaces
            # can go through unchanged.  Note that if you use space identifiers
            # without square brackets in your surrounding MDX, your query will
            # not execute.
            #
            } else {
                $value =~ s/[^a-z0-9_\-\s]//ig;
                $mdx2 .= $value;
            }

        } else {
            $mdx2 .= $bits[$idx];
        }
    }

    return $mdx2;
}



################################################################################
# Loads a specified MDX statement from the datasets, transforms the MDX into
# placeholder, pulls out the variable names, and prepares a statement.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $dsxml - Dataset XML object
#       $dbh - Database handle
#       $args_href - Hash of args to substitute.
#
# Returns:
#       $mdx statement with args substituted.
################################################################################
#
sub parse_mdx {
    my ($jconfig, $dsxml, $args_href) = @_;

    # Get the raw values.
    my $raw_mdx = $dsxml->{dataset}{'mdx'}->content || return undef;
    $raw_mdx =~ s/^\s*\-\-.*$//gm;   # Remove comments
    $raw_mdx = &trim ($raw_mdx);

    # Perform textual substitution... being vary careful about injection!    
    &Jarvis::Error::dump ($jconfig, "MDX as read from XML = " . $raw_mdx);

    # Get our MDX with placeholders and prepare it.
    my $mdx = &mdx_with_substitutions ($jconfig, $raw_mdx, $args_href);
    &Jarvis::Error::dump ($jconfig, "MDX after substition = " . $mdx);

    return $mdx;
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
#       $jconfig - Jarvis::Config object
#           READ
#               cgi                 Contains data values for {{param}} in MDX
#               username            Used for {{username}} in MDX
#               group_list          Used for {{group_list}} in MDX
#               format              Either "json" or "xml" or "csv".
#
#       $subset_name - Name of single dataset we are fetching from.
#       $dsxml - Dataset's XML configuration object.
#       $dbh - Database handle of the correct type to match the dataset.
#       $safe_params_href - All our safe parameters.
#
# Returns:
#       $num_fetched - Raw number of rows fetched from DB, for paging.
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
#       $extra_href - Hash of dataset-level parameters set by hooks. 
################################################################################
#
sub fetch {
    my ($jconfig, $subset_name, $dsxml, $dbh, $safe_params_href) = @_;
    
    # Get our STM.  This has everything attached.
    my $mdx = &parse_mdx ($jconfig, $dsxml, $safe_params_href) ||
        die "Dataset '$subset_name' (type 'sdp') has no MDX query.";

    # What key will we use to store the row labels?
    my $row_label = $dsxml->{dataset}{mdx}{row_label} || 'row_label';
        
    # Execute Fetch in 2D tuple format.
    my ($rows_aref, $column_names_aref) = $dbh->fetchall_arrayref ($jconfig, $mdx, $row_label);
    
    my $num_fetched = scalar @$rows_aref;
    &Jarvis::Error::debug ($jconfig, "Number of rows fetched = $num_fetched.");

    # Do we want to do server side sorting?  This happens BEFORE paging.  Note that this
    # will only work when $sth->{NAME} is available.  Some (all?) stored procedures
    # under MS-MDX Server will not provide field names, and hence this feature will not
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

    # This final hook allows you to modify the data returned by MDX for one dataset.
    # This hook may do one or both of:
    #
    #   - Completely modify the returned content (by modifying $rows_aref)
    #   - Add additional per-dataset scalar parameters (by setting $extra_href)
    #
    my $extra_href = {};
    &Jarvis::Hook::dataset_fetched ($jconfig, $dsxml, $safe_params_href, $rows_aref, $extra_href);
                            
    return ($num_fetched, $rows_aref, $column_names_aref, $extra_href); 
}


1;
