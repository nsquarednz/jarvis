# This startup.pl is run via PerlRequire in the http configuration, e.g.
#
# PerlRequire /etc/jarvis/apache/startup.pl
#
# This is run once only, for each mod_perl server process started for this
# Jarvis agent.
#

# This gives us transparant database connection pooling.  "Disconnected"
# connections are put back into the pool.
#
use Apache::DBI;

# This enables us to find Jarvis::Agent in standard locations.
use lib qw(/usr/share/jarvis/lib);      # For Debian.
use lib qw(/opt/jarvis/lib);            # For other systems.

1;
