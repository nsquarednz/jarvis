###############################################################################
# Description:  XSLoader wrapper around Jarvis/JSON/Utils/Utils.xs # # Licence:      (c) 2019 by N-Squared Software (NZ) Limited.
#               All Rights Reserved.
#
#               All information contained herein is, and remains
#               the property of N-Squared Software (NZ) Limited.
#
#               The intellectual and technical concepts contained herein are
#               proprietary to N-Squared Software (NZ) Limited, and are
#               protected by trade secret or copyright law.
#
#               Dissemination of this information or reproduction of this
#               material is strictly forbidden unless prior written permission
#               is obtained from N-Squared Software (NZ) Limited.
###############################################################################
#
use strict;
use warnings;

package Jarvis::JSON::Utils;

require XSLoader;

XSLoader::load();

1;