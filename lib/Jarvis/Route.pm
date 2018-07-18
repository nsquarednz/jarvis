###############################################################################
# Description:  The Route::find method identifies the first match from the
#               $jconfig routing list, and performs the parameter lookup to
#               turn numbered restful args into named substitution args.
#
#               If no route matches, use $rest_arg[0] as the dataset-name.
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

package Jarvis::Route;

use Jarvis::Error;

################################################################################
# Parses a URL, finds the best route, and performs parameter substitution.
# We pull out any named REST args and merge them with our numbered rest args
# array to form a complete combined REST args hash.
# 
# Fallback to $rest_args[0]
#
# Params:
#       $path_parts - Numbered rest args starting from 0.
#
# Returns:
#       $dataset_name - Dataset name from route, or from <arg0>
#       $named_rest_args - Hash of named AND indexed rest args after route parsing.
#       $presentation - Should restful encodings return an "array" or "singleton".
################################################################################
#
sub find {
    my ($jconfig, $path_parts) = @_;

    $jconfig || die;

    # Copy numbered rest args into a hash.
    my %numbered_rest_args = ();
    foreach my $i (0 .. $#$path_parts) {
        $numbered_rest_args{$i} = $$path_parts[$i];
    }

    # Load routes and store in $jconfig, just in case we need them again.
    if (! defined ($jconfig->{routes})) {
        my @routes = ();
        
        my $rxml = $jconfig->{'xml'}{'jarvis'}{'app'}{'router'};
        if ($rxml && $rxml->{'route'}) {
            foreach my $route ($rxml->{'route'}('@')) {
                (defined $route->{dataset}) || die "Router has route with no dataset.\n";
                (defined $route->{path}) || die "Router has route with no path.\n";
                my $dataset = $route->{dataset}->content;
                my $path = $route->{path}->content;
                my $presentation = $route->{presentation} ? $route->{presentation}->content : "array";
                ($presentation eq 'array') || ($presentation eq 'singleton') || die "Unsupported presentation '$presentation' in route.\n";

                # Remove leading slash to expose the first path part.
                ($path =~ m|^/|) || die "Route path does not begin with leading '/'.\n";
                $path =~ s|^/||;
                my (@parts) = map { s/^\s+//; s/\s+$//; $_; } split ( m|/|, $path, -1);

                push (@routes, { dataset => $dataset, path => $path, parts => \@parts, presentation => $presentation});
            }
        }
        &Jarvis::Error::debug ($jconfig, "Loaded %d route(s).", scalar @routes);

        $jconfig->{routes} = \@routes;
    }

    # Find the first matching route.
    foreach my $route (@{ $jconfig->{routes} }) {
        &Jarvis::Error::dump ($jconfig, "Try Match Route: '%s'.", $route->{path});

        # Make sure each part matches.
        my $match = 1;
        my $route_parts = $route->{parts};
        my %rest_args = %numbered_rest_args;

        foreach my $i (0 .. $#$route_parts) {
            my $route_part = $$route_parts[$i];
            my $given_part = $$path_parts[$i];
            &Jarvis::Error::dump ($jconfig, "Part [$i].  Route = '%s', Given = '%s'.", $route_part, $given_part);

            # An empty route part is a mid-path // or /:/ or /*/, or follows a trailing /.  Match anything except undef.
            if (($route_part eq '') || ($route_part eq ':') || ($route_part eq '*')) {
                if (defined $given_part) {
                    &Jarvis::Error::dump ($jconfig, "Empty/Wildcard Route Part matched.");
                    next;

                } else {
                    &Jarvis::Error::dump ($jconfig, "Empty/Wildcard Route Part not matched.");
                    $match = 0;
                    last;
                }

            # A part starting with ":" is a collection variable.  Match anything except undef.
            } elsif ($route_part =~ m|^:(.+)$|) {
                if (defined $given_part) {
                    my $collected_name = $1;
                    &Jarvis::Error::dump ($jconfig, "Collection Route Part matched.  Variable '%s' => '%s'.", $collected_name, $given_part);
                    $rest_args{$collected_name} = $given_part;
                    next;

                } else {
                    &Jarvis::Error::dump ($jconfig, "Collection Route Part not matched.");
                    $match = 0;
                    last;
                }

            # Any other part must match exactly.
            } else {
                if ((defined $given_part) && ($given_part eq $route_part)) {
                    &Jarvis::Error::dump ($jconfig, "Static Route Part '%s' matched.", $route_part);
                    next;

                } else {
                    &Jarvis::Error::dump ($jconfig, "Static Route Part not matched.");
                    $match = 0;
                    last;
                }
            }
        }

        # Did we get a route match?
        if ($match) {
            my $dataset_name = $route->{dataset};
            &Jarvis::Error::debug ($jconfig, "Completed route match '%s' -> dataset '%s'.", $route->{path}, $dataset_name);
            return ($dataset_name, \%rest_args, $route->{presentation});
        }
    }

    # Default logic, use arg0 as the dataset name, and no named args.
    my $dataset_name = $$path_parts[0];
    &Jarvis::Error::debug ($jconfig, "No route match.  Using arg0 as dataset_name '%s'.", $dataset_name);

    return ($dataset_name, \%numbered_rest_args, "array");
}

1;
