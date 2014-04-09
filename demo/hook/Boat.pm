###############################################################################
# Description:  Demo per-Dataset hook module.
###############################################################################
#
use strict;
use warnings;

package Boat;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

###############################################################################
# HOOKS
###############################################################################

sub Boat::start {
    my ($jconfig, $hook_params_href) = @_;

    &Jarvis::Error::debug ($jconfig, "Boat::start: Quota = '%s'.", $hook_params_href->{quota});
    $jconfig->{__boat_index} = $hook_params_href->{index} || 'Unchecked';

    return 1;
}

sub Boat::return_fetch {
    my ($jconfig, $hook_params_href, $safe_row_params_href, $return_object, $extra_href, $return_text_ref) = @_;

    $extra_href->{boat_index} = $jconfig->{__boat_index};

    return 1;
}

# Strip trailing "!" from name on save.
sub Boat::before_one {
    my ($jconfig, $hook_params_href, $dsxml, $safe_row_params_href) = @_;

    if (defined $safe_row_params_href->{name}) {
        $safe_row_params_href->{name} =~ s/\!+$//;
    }

    return 1;
}

# Fix another common spelling error.  Try:
#   http://localhost/jarvis-agent/demo/boat/by-class/X-Class
sub Boat::dataset_pre_fetch {
    my ($jconfig, $hook_params_href, $dsxml, $safe_params_href) = @_;

    if ($safe_params_href->{boat_class} eq 'X-Class') {
        $safe_params_href->{boat_class} = 'X Class';
    }

    return 1;
}

1;