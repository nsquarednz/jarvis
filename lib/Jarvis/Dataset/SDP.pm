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

    foreach my $k (keys %{$args_href}) {
        &Jarvis::Error::debug ($jconfig, "MDX substitution: $k -> $args_href->{$k}.");
    }

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
                $value =~ s/[^0-9a-zA-Z _\-,]//ig;                
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
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
################################################################################
#
sub fetch {
    my ($jconfig, $subset_name, $dsxml, $dbh, $safe_params_href) = @_;
    
    # Get our STM.  This has everything attached.
    my $mdx = &parse_mdx ($jconfig, $dsxml, $safe_params_href) ||
        die "Dataset '$subset_name' (type 'sdp') has no MDX query.";

    # What key will we use to store the row labels?
    my $row_label = $dsxml->{dataset}{mdx}{row_label}->content || 'row_label';
        
    # Execute Fetch in 2D tuple format.
    my ($rows_aref, $column_names_aref) = $dbh->fetchall_arrayref ($jconfig, $mdx, $row_label);    

    return ($rows_aref, $column_names_aref); 
}

################################################################################
# Loads the data for the current dataset(s), and puts it into our return data
# array so that it can be presented to the client in JSON or XML or whatever.
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return 
# object.
#
# This variant is for 3D MDX queries only.  I.e. those that specify ROW and
# COLUMN and PAGE.
#
# Note that the result from this call is a HASH, not an ARRAY! This will 
# probably confuse the heck out of any hook.
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
#       $data_href - Three Dimensional nested hash.
################################################################################
#
sub fetch_3d {
    my ($jconfig, $subset_name, $dsxml, $dbh, $safe_params_href) = @_;
    
    # Get our STM.  This has everything attached.
    my $mdx = &parse_mdx ($jconfig, $dsxml, $safe_params_href) ||
        die "Dataset '$subset_name' (type 'sdp') has no MDX query.";

    # What key will we use to store the row labels?
    my $row_label = $dsxml->{dataset}{mdx}{row_label}->content || 'row_label';
        
    # Execute Fetch in 2D tuple format.
    my ($data_href) = $dbh->fetchall_hashref_3d ($jconfig, $mdx, $row_label);    

    return ($data_href); 
}

1;
