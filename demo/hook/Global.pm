###############################################################################
# Description:  Demo Global hook module.
###############################################################################
#
use strict;
use warnings;

package Global;

use Jarvis::Config;
use Jarvis::Error;
use Jarvis::Text;

###############################################################################
# HOOKS
###############################################################################

sub Global::start {
    my ($jconfig, $hook_params_href) = @_;

    &Jarvis::Error::debug ($jconfig, "Global::start: Quota = '%s'.", $hook_params_href->{quota});
    $jconfig->{__quota} = $hook_params_href->{quota};

    return 1;
}

# Add "quota" to __status return.
sub Global::return_status {
    my ($jconfig, $hook_params_href, $extra_href, $return_text_ref) = @_;

    $extra_href->{quota} = $jconfig->{__quota};

    return 1;
}

# Add "quota" to __fetch return.
sub Global::return_fetch {
    my ($jconfig, $hook_params_href, $user_args_href, $rows_aref, $extra_href, $return_text_ref) = @_;

    # Duplicate the first row if requested.    
    if ($user_args_href->{duplicate}) {
        my %copy = %{ $$rows_aref[0] };
        push (@$rows_aref, \%copy);
    }

    # Always add our quota.
    $extra_href->{quota} = $jconfig->{__quota};

    return 1;
}

# Fix another common spelling error.  Try:
#   http://localhost/jarvis-agent/demo/boat/by-class/Makleson
sub Global::dataset_pre_fetch {
    my ($jconfig, $hook_params_href, $dsxml, $safe_params_href) = @_;

    if (defined $safe_params_href->{boat_class}) {
        if ($safe_params_href->{boat_class} eq 'Makleson') {
            $safe_params_href->{boat_class} = 'Makkleson';
        }
    }

    return 1;
}

1;