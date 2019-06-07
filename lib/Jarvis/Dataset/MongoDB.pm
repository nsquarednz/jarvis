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

use XML::Smart;
use JSON;

package Jarvis::Dataset::MongoDB;

use Jarvis::Text;
use Jarvis::Error;
use Jarvis::DB;
use Jarvis::Hook;

use sort 'stable';      # Don't mix up records when server-side sorting

my $json = JSON->new ();

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
#       $mdx_with_substitutions
################################################################################
#
sub mdx_with_substitutions {

    my ($jconfig, $mdx, $args_href) = @_;

    # Dump the available arguments at this stage.
    foreach my $k (keys %{$args_href}) {
        &Jarvis::Error::dump ($jconfig, "MDX available args: '$k' -> '$args_href->{$k}'.");
    }

    # Parameters NAMES may contain only a-z, A-Z, 0-9, underscore(_), colon(:), dot(.) and hyphen(-)
    # Note pipe(|) is also allowed at this point as it separates (try-else variable names)
    #
    my @bits = split (/\{\$([\.a-zA-Z0-9_\-:\|]+(?:\![a-z]+)*)\}/i, $mdx);

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
            #   !string - Escape suitable for use in StrToMbr(" ")
            #   !bracket - Use ]] for ].  Allow most others.
            #
            # Note, I sat for quite a while here wondering if we should make the
            # system a bit "smarter", i.e. allow it to examine the surrounding
            # context for each value to determine if e.g. it was preceded by an
            # open bracket, and we should automatically activate the :bracket
            # flag.  But in the end, I just couldn't see that it was going to be
            # 100% safe or reliable.  So let's leave it in the query designer's
            # hands, and just default to "safe" mode. 
            #
            while ($name =~ m/^(.*)(\![a-z]+)$/) {
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

            # With the !string flag, or if the preceding character was a string, 
            # then escape for use in StrToMbr(" ")
            if ($flags{'string'}) {
                $value =~ s/\\/\\\\/g;
                $value =~ s/"/\\"/g;
                
            # We can allow brackets. 
            } elsif ($flags{'bracket'}) {
                $value =~ s/\]/\]\]/g;
                
            # Else we go raw.  Only allowed for SAFE variables (not client-supplied). 
            } elsif ($flags{'raw'} && ($name =~ m/^__/)) {
                # No change.
                
            # Or else we will just use plain identifiers.  Characters and spaces
            # can go through unchanged.  Note that if you use space identifiers
            # without square brackets in your surrounding MDX, your query will
            # not execute.
            #
            } else {
                $value =~ s/[^0-9a-zA-Z _\-,]//ig;                
            }
            &Jarvis::Error::debug ($jconfig, "Expanding: '$name' " . (scalar %flags ? ("[" . join (",", keys %flags) . "] ") : "") . "-> '$value'.");            
            $mdx2 .= $value;

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
#       $oxml - Dataset XML object at a point within the tree.
#       $args_href - Hash of args to substitute.
#
# Returns:
#       $mdx statement with args substituted.
################################################################################
#
sub parse_object {
    my ($jconfig, $oxml, $args_href) = @_;

    # Get the raw JSON.
    my $object_json = $oxml->content // return undef;

    # Convert to perl object.
    my $object = $json->decode ($object_json);

    # Iterate and replace {$VARNAME} with the variable.
    sub expand_vars {
        my ($jconfig, $var_ref, $args_href) = @_;

        # undef - no change.
        if (! defined $$var_ref) {
            # Do nothing.

        # SCALAR ... this is where we expand!
        } elsif (ref ($$var_ref) eq '') {
            if ($$var_ref =~ m/^\{\$([\.a-zA-Z0-9_\-:\|]+(?:\![a-z]+)*)\}/) {

                # Here's the arg name.  For now it has flags.
                my $argname = $1;

                # Strip all the !flag from the tail.
                # By the way, we don't actually SUPPORT any flags yet!
                my %flags = ();
                while ($argname =~ m/^(.*)(\![a-z]+)$/) {
                    $argname = $1;
                    my $flag = lc ($2);
                    $flag =~ s/[^a-z]//g;
                    $flags {$flag} = 1;
                }

                my $value = $$var_ref = $args_href->{$argname};
                &Jarvis::Error::debug ($jconfig, "Expanding: '%s' %s -> '%s'.", $argname, (scalar %flags ? ("[" . join (",", keys %flags) . "] ") : ""), $value);
            }

        # ARRAY
        } elsif (ref ($$var_ref) eq 'ARRAY') {
            foreach my $var (@{ $$var_ref }) {
                &expand_vars ($jconfig, \$var, $args_href);
            }

        # HASH
        } elsif (ref ($$var_ref) eq 'HASH') {
            foreach my $key (keys %{ $$var_ref }) {
                &expand_vars ($jconfig, \$$var_ref->{$key}, $args_href);
            }

        # ¯\_(ツ)_/¯
        } else {
            # Do nothing.
        }
        return;
    }
    &expand_vars ($jconfig, \$object, $args_href);

    return $object;
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
sub fetch_inner {
    my ($jconfig, $subset_name, $dsxml, $dbh, $safe_params_href) = @_;

    # Start with the collection.  This is at the top level of the datasets.
    # TODO: Maybe allow different operations to override the collection name?
    $dsxml->{dataset}{collection} or die "Dataset '$subset_name' (type 'mongo') has no 'collection' defined.\n";
    my $collection_name = $dsxml->{dataset}{collection}->content;

    # We must also have a <find> block present in the dataset.  
    # It MUST be present for find to be supported, EVEN IF IT IS EMPTY.
    $dsxml->{dataset}{find} or die "Dataset '$subset_name' (type 'mongo') has no 'find' present.\n";

    # Do we have a filter?  It can be undef, it's purely optional.
    my $filter = undef;
    if ($dsxml->{dataset}{find}{filter}) {
        $filter = &parse_object ($jconfig, $dsxml->{dataset}{find}{filter}, $safe_params_href);
    }

    # This is the collection handle.
    my $collection = $dbh->ns ($collection_name);
    
    # Find one row.
    my $cursor = $collection->find ($filter);    
    my $rows_aref = [];

    while (my $document = $cursor->next ) {
        push (@$rows_aref, $document);
    }

    return ($rows_aref); 
}

1;
