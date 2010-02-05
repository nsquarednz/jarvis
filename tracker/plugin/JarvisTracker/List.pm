###############################################################################
# Description:
#       Jarvis plugin to provide a list of details about a specific application or
#       dataset, depending on the level provided.
#
#       The 'node' - i.e. place to get in the tree is given by the 'node' URL argument
#       - a RESTful approach would have been nicer, but as we're currently using EXT
#       and the default tree loader works with this 'node' argument.
#
# Licence:
#       This file is part of the Jarvis Tracker application.
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
#       This software is Copyright 2008 by Jamie Love.
###############################################################################

use strict;
use warnings;

package JarvisTracker::List;

use JSON::PP;
use Jarvis::DB;

sub JarvisTracker::List::do {
    my ($jconfig, $restArgs) = @_;

    my @list;
    my $id = $jconfig->{'cgi'}->param('node');

    die "Please provide parameter 'node'" if !$id;

    my @parts = split /\//, $id;

    # Check that each part is safe. We can't have the user
    # passing in paths that could let them access files outside
    # the application directories.
    map {
        die "ERROR in node provided. Node must be made up of characters: A-Z, a-z, 0-9, _, - and space only." if ! /^[-A-Za-z0-9_ ]*$/;
    } @parts;

    #
    # For the root node, return the list of applications from the Jarvis etc directory.
    # Only look at files ending in .xml
    if (!$id || $id eq 'root') {
        opendir (APPS, $jconfig->{'etc_dir'} );
        my @files = grep (/\.xml$/, readdir (APPS));
        closedir (APPS);
        map { 
            $_ =~ s/\.xml$//;
            push(@list, { id => $_, text => $_, icon => 'style/application_form.png' }); 
        } @files;
    } else {
        #
        # If there is only one part, it must be (or is expected to be) the application
        # name, so return a pre-defined list of types of objects under the app.
        if (@parts == 1) {
            push (@list, {
                id => "$id/Errors",
                text => "Errors",
                leaf => 1,
                icon => "style/exclamation.png"
            });
            push (@list, {
                id => "$id/Datasets",
                text => "Datasets",
                icon => "style/script_code.png"
            });
            push (@list, {
                id => "$id/Users",
                text => "Users",
                icon => "style/user_gray.png"
            });
            push (@list, {
                id => "$id/Events",
                text => "Events",
                icon => 'style/timeline_marker.png',
                leaf => 1
            });
        } else {
            #
            # If there are more than 2 parts, then we're looking at a specific 
            # lower level item within an item - Datasets, Errors, Users or Plugins

            #
            # Datasets of all flavours - SQL datasets, plugins, exec's and builtins
            #
            if ($parts[1] eq "Datasets") {

                #
                # Now SQL queries from dataset files.
                #
                my $xmlFilename = $jconfig->{'etc_dir'} . "/" . $parts[0] . ".xml";
                my $xml = XML::Smart->new ($xmlFilename) || die "Cannot read configuration for $parts[0].xml: $!.";
                my $datasetDirectory = $xml->{jarvis}{app}{dataset_dir}->content;
                my $inSubdirectory = 0;

                if (@parts > 2) {
                    $inSubdirectory = 1;
                    splice(@parts, 0, 2);
                    $datasetDirectory .= "/" . (join "/", @parts); # all parts have been previously checked for safety - no '..' or other unsafe characters are included.
                }

                opendir (QUERIES, $datasetDirectory) || die "Cannot read queries for '$id'. $!.";
                my @files = grep (!/^\./, readdir (QUERIES));
                closedir (QUERIES);
                map { 
                    if ($_ =~ /\.xml$/) {
                        $_ =~ s/\.xml$//;
                        push(@list, { id => "$id/$_", text => $_, leaf => 1, icon => 'style/bullet_blue.png' }); 
                    } elsif (-d $datasetDirectory . "/" . $_) {
                        opendir (QUERIES, $datasetDirectory . "/" . $_);
                        my @testq = grep (/\.xml$/, readdir(QUERIES));
                        closedir (QUERIES);
                        if (@testq > 0) {
                            push(@list, { id => "$id/$_", text => $_ }); 
                        }
                    }
                } @files;

                # If top level - don't do this for subdirectory SQL queries..
                if ($inSubdirectory == 0) {
                    #
                    # Builtins
                    #
                    map {
                        push (@list, { id => "$id/$_", text => $_, leaf => '1', datasetType => 'builtin', icon => 'style/server.png' });
                    } qw(__status __logout __habitat);

                    #
                    # Now plugins and 'exec' options
                    #
                    my @plugins = $xml->{jarvis}{app}{plugin}('@');
                    map {
                        push(@list, { 
                            id => "$id/" . $_->{dataset}->content, 
                            text => $_->{dataset}->content, 
                            leaf => 1,
                            icon => 'style/plugin.png' 
                        }); 
                    } @plugins;

                    my @execs = $xml->{jarvis}{app}{exec}('@');
                    map {
                        push(@list, { id => "$id/" . $_->{dataset}->content, text => $_->{dataset}->content, leaf => 1, icon => 'style/application_xp_terminal.png' }); 
                    } @execs;
                }
            #
            # Users
            #
            } elsif ($parts[1] eq "Users") {
                my $dbh = &Jarvis::DB::handle ($jconfig);
                my $sql = "SELECT DISTINCT username FROM request WHERE app_name = ?";
                my $sth = $dbh->prepare ($sql) || die "Couldn't prepare statement for listing users: " . $dbh->errstr;
                my $stm = {};
                $stm->{sth} = $sth;
                $stm->{ttype} = 'JarvisTrackerList-users';
                my $params = [ $parts[0] ];
                &Jarvis::Dataset::statement_execute ($jconfig, $stm, $params);
                $stm->{'error'} && die "Unable to execute statement for listing users: " . $dbh->errstr;

                my $users = $sth->fetchall_arrayref({});
                map {
                    my $u = $_->{username};
                    push(@list, { id => "$id/$u", text => (length($u) == 0 ? '(none)' : $u), leaf => 1, icon => 'style/bullet_yellow.png' }); 
                } @{$users};
            #
            # Plugins and execs
            #
            } elsif ($parts[1] eq "Plugins") {

            }
        }
    }

    my @sorted = sort { lc($a->{text}) cmp lc($b->{text}) } @list;

    my $json = JSON::PP->new->pretty(1);
    return $json->encode ( \@sorted );
}


1;

