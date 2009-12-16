###############################################################################
#
# Jarvis plugin to provide a list of details about a specific application or
# dataset, depending on the level provided.
#
###############################################################################

use strict;
use warnings;

use JSON::XS;

package JarvisTrackerList;

sub JarvisTrackerList::do {
    my ($jconfig, %args) = @_;

    my $id = $jconfig->{'cgi'}->param('node');

    my $list = [];

    if (!$id || $id eq 'root') {
        opendir (APPS, "/opt/jarvis/etc/");
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
                        push(@{$list}, { id => "$id/$_", text => $_, leaf => "true" }); 
                    } elsif (-d $datasetDirectory . "/" . $_) {
                        opendir (QUERIES, $datasetDirectory . "/" . $_);
                        my @testq = grep (/\.xml$/, readdir(QUERIES));
                        closedir (QUERIES);
                        if (@testq > 0) {
                            push(@{$list}, { id => "$id/$_", text => $_ }); 
                        }
                    }
                } @files;
            }
        }
    }

    my $json = JSON::XS->new->pretty(1);
    return $json->encode ( $list );
}


1;

