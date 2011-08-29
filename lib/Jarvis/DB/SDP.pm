##############################################################################
# Implements Jarvis::DB::SDP
#
# This class implements a pseudo database interaction with the SSAS 
# DataPump HTTP(S) service.
#
# This is invoked with
#  <database type="sdp" ... > 
#
# in the Jarvis application config file. 
##############################################################################
#
use strict;
use warnings;

package Jarvis::DB::SDP;

BEGIN {
    our @ISA = qw (Exporter);
    our @EXPORT = qw ();

    require Exporter;
}

##############################################################################
##############################################################################
# OBJECT LOADERS AND FINDERS
##############################################################################
##############################################################################

sub new {
    my ($class, $jconfig, $connect, $username, $password, $parameters) = @_;
   
    my $self = {};
    bless $self, $class;
    
    $self->init ($jconfig, $connect, $username, $password, $parameters);
    return $self;
}

sub init {
    my ($jconfig, $connect, $username, $password, $parameters) = @_;
    
    $self->connect = $connect;
    $self->username = $username;
    $self->password = $password;
    $self->parameters = $parameters;
}

# Dummy function.  We do not have a permanent connection.
sub disconnect {
}
