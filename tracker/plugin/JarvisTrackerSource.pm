###############################################################################
#
# Jarvis plugin to provide a list of details about a specific application or
# dataset, depending on the level provided.
#
###############################################################################

use strict;
use warnings;

package JarvisTrackerSource;

use JSON::XS;
use Jarvis::DB;

# TODO This is not really safe in terms of directory path creation
sub JarvisTrackerSource::do {
    my ($jconfig, $restArgs) = @_;

    my $configFilename = $jconfig->{'etc_dir'} . "/" . $restArgs->[0] . ".xml";
    my $config = XML::Smart->new ($configFilename) || die "Cannot read '$configFilename': $!.";
    my $datasetDirectory = $config->{jarvis}{app}{dataset_dir}->content;

    my $section = $restArgs->[1];
    my $filename = $datasetDirectory;
    splice(@{$restArgs}, 0, 2);
    map { $filename .= "/" . $_; } @{$restArgs};
    $filename .= ".xml";
    my $dsxml = XML::Smart->new ($filename) || die "Cannot read '$filename': $!\n";
    return $dsxml->{dataset}->{$section}->content;
}


1;


