###############################################################################
# Description:  Demo per-Dataset hook module.
###############################################################################
#
use strict;
use warnings;

package Bar;

use Data::Dumper;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

###############################################################################
# HOOKS
###############################################################################

sub Bar::dataset_fetched {
    my ($jconfig, $hook_params_href,  $dsxml, $safe_params_href, $rows_aref, $extra_href, $column_names_aref) = @_;

    foreach my $row (@$rows_aref) {
        $row->{bar} = 'Bar';
    }

    return 1;
}


1;