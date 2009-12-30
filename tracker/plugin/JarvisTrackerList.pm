###############################################################################
#
# Jarvis plugin to provide a list of details about a specific application or
# dataset, depending on the level provided.
#
# The 'node' - i.e. place to get in the tree is given by the 'node' URL argument
# - a RESTful approach would have been nicer, but as we're currently using EXT
# and the default tree loader works with this 'node' argument.
#
###############################################################################

use strict;
use warnings;

package JarvisTrackerList;

use JSON::XS;
use Jarvis::DB;

# TODO This is not really safe in terms of directory path creation
sub JarvisTrackerList::do {
    my ($jconfig, $restArgs) = @_;

    my $id = $jconfig->{'cgi'}->param('node');

    my $list = [];

    if (!$id || $id eq 'root') {
        opendir (APPS, $jconfig->{'etc_dir'} );
        my @files = grep (/\.xml$/, readdir (APPS));
        closedir (APPS);
        map { 
            $_ =~ s/\.xml$//;
            push(@{$list}, { id => $_, text => $_ }); 
        } @files;
    } else {
        my @parts = split /\//, $id;
        if (@parts == 1) {
            my @areas = ("errors", "plugins", "queries", "users");
            map {
                push(@{$list}, { id => "$id/$_", text => $_ }); 
            } @areas;
        } else {
            if ($parts[1] eq "queries") {
                my $xmlFilename = $jconfig->{'etc_dir'} . "/" . $parts[0] . ".xml";
                my $xml = XML::Smart->new ($xmlFilename) || die "Cannot read '$xmlFilename': $!.";
                my $datasetDirectory = $xml->{jarvis}{app}{dataset_dir}->content;

                if (@parts > 2) {
                    splice(@parts, 0, 2);
                    map {$datasetDirectory .= "/" . $_} @parts;
                }

                opendir (QUERIES, $datasetDirectory) || die "Cannot read queries for '$id' - Dir was '$datasetDirectory'. $!.";
                my @files = grep (!/^\./, readdir (QUERIES));
                closedir (QUERIES);
                map { 
                    if ($_ =~ /\.xml$/) {
                        $_ =~ s/\.xml$//;
                        push(@{$list}, { id => "$id/$_", text => $_, leaf => 1 }); 
                    } elsif (-d $datasetDirectory . "/" . $_) {
                        opendir (QUERIES, $datasetDirectory . "/" . $_);
                        my @testq = grep (/\.xml$/, readdir(QUERIES));
                        closedir (QUERIES);
                        if (@testq > 0) {
                            push(@{$list}, { id => "$id/$_", text => $_ }); 
                        }
                    }
                } @files;
            } elsif ($parts[1] eq "users") {
                my $dbh = &Jarvis::DB::handle ($jconfig);
                my $sql = "SELECT DISTINCT username FROM request WHERE app_name = ?";
                my $sth = $dbh->prepare ($sql) || die "Couldn't prepare statement '$sql': " . $dbh->errstr;
                my $stm = {};
                $stm->{sth} = $sth;
                $stm->{ttype} = 'JarvisTrackerList-users';
                my $params = [ $parts[0] ];
                &Jarvis::Dataset::statement_execute ($jconfig, $stm, $params);
                $stm->{'error'} && die "Unable to execute statement '$sql': " . $dbh->errstr;

                my $users = $sth->fetchall_arrayref({});
                map {
                    my $u = $_->{username};
                    push(@{$list}, { id => "$id/$u", text => $u, leaf => 1 }); 
                } @{$users};
            } elsif ($parts[1] eq "plugins") {
                my $xmlFilename = $jconfig->{'etc_dir'} . "/" . $parts[0] . ".xml";
                my $xml = XML::Smart->new ($xmlFilename) || die "Cannot read '$xmlFilename': $!.";
                my @plugins = $xml->{jarvis}{app}{plugin}('@');

                map {
                    push(@{$list}, { id => "$id/$_->{dataset}->content", text => $_->{dataset}->content, leaf => 1 }); 
                } @plugins;
            }
        }
    }

    my $json = JSON::XS->new->pretty(1);
    return $json->encode ( $list );
}


1;

