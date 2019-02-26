###############################################################################
# Description:  Demo Global2 hook module.
###############################################################################
#
use strict;
use warnings;

package Global2;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

###############################################################################
# HOOKS
###############################################################################

sub Global2::start {
    my ($jconfig, $hook_params_href) = @_;

    &Jarvis::Error::debug ($jconfig, "Global2::start: Sideband = '%s'.", $hook_params_href->{sideband});
    $jconfig->{__sideband} = $hook_params_href->{sideband};

    return 1;
}

# Add "sideband" to __status return.
sub Global2::return_status {
    my ($jconfig, $hook_params_href, $extra_href, $return_text_ref) = @_;

    $extra_href->{sideband} = $jconfig->{__sideband};

    return 1;
}

# Add "sideband" to __fetch return.
sub Global2::return_fetch {
    my ($jconfig, $hook_params_href, $user_args_href, $rows_aref, $extra_href, $return_text_ref) = @_;

    # Always add our sideband.
    $extra_href->{sideband} = $jconfig->{__sideband};

    return 1;
}

# Fix another common spelling error.  Try:
#   http://localhost/jarvis-agent/demo/boat/by-class/Makleson
sub Global2::dataset_pre_fetch {
    my ($jconfig, $hook_params_href, $dsxml, $safe_params_href) = @_;

    if (defined $safe_params_href->{boat_class}) {
        if ($safe_params_href->{boat_class} eq 'Makleson') {
            $safe_params_href->{boat_class} = 'Makkleson';
        }
    }

    return 1;
}

1;