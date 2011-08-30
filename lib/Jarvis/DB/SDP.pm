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

use MIME::Base64;
use SOAP::Lite;
use Data::Dumper;
use XML::Smart;

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
    my ($self, $jconfig, $connect, $username, $password, $parameters) = @_;
    
    $self->{'connect'} = $connect;
    $self->{'username'} = $username;
    $self->{'password'} = $password;
    $self->{'parameters'} = $parameters;

    # Create the client SOAP handle.
    my $soap = SOAP::Lite->new( proxy => $connect);
    
    $soap->readable(1);
    $soap->autotype(0);
    $soap->outputxml(1);
    $soap->default_ns('urn:schemas-microsoft-com:xml-analysis');
    $soap->transport->http_request->header ('Authorization' => 'Basic ' . MIME::Base64::encode("$username:$password"));
    $self->{'soap'} = $soap;    
}

##############################################################################
##############################################################################
# METHODS
##############################################################################
##############################################################################

# Dummy function.  We do not have a permanent connection.
sub disconnect {
}

################################################################################
# Makes the specified MDX request, and returns the XML object for another
# method to process.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $mdx - Query to execute
#
# Returns:
#       $response - XML object of successful response.
################################################################################
#
sub fetchall {
    
    my ($self, $jconfig, $mdx) = @_;
    
    &Jarvis::Error::debug ($jconfig, "Performing Execute request to SSAS DataPump.");
    
    my @property_list = ( 
        SOAP::Data->value(
            SOAP::Data->name('Catalog')->value('ExonetAnalysis'),
        )
    );
                    
    my $soap = $self->{'soap'};
    my $rxml = $soap->call('Execute',         
        SOAP::Data->name('Command')->value(
            \SOAP::Data->value(
                SOAP::Data->name('Statement')->value($mdx)
            )
        ),
        SOAP::Data->name('Properties')->value(
            \SOAP::Data->value(
                SOAP::Data->name('PropertyList')->value(
                    \@property_list
                )
            )
        )
    );
    
    # Check for errors.
    my $response = XML::Smart->new ($rxml) || die "Malformed XML on SDP response.";
    $response->{'soap:Envelope'}->{'soap:Body'} || die "No soap:Envelope/soap:Body found in SDP response.";
    
    if ($response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}) {
        my $description = $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'Description'}->content || 'SOAP Fault returned from SDP request.';
        my $error_code = $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'ErrorCode'}->content || 'unknown';
        my $source = $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'Source'}->content || 'SSAS DataPump';
        die "$source returned error $error_code: $description";
    }
    
    return $response;
}
    
################################################################################
# Makes the specified MDX request, and 
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return 
# object.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $mdx - Query to execute
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
#       $row_names_aref - Array of tuple row names, if available.
################################################################################
#
sub fetchall_arrayref {
    my ($self, $jconfig, $mdx) = @_;
    
    # Get the raw data.
    my $response = $self->fetchall ($jconfig, $mdx);
    
    &Jarvis::Error::debug ($jconfig, "Converting to Array of tuples.");

    # Now the fun bit.  Convert the deep complicated structure into 2D tuple array like DBI would.
    # print STDERR &Dumper (keys %{ $response->{'soap:Envelope'}->{'soap:Body'}->{'soap:Fault'}->{'detail'}->{'Error'}->{'Description'} });    

    return ([], []);
}

1;
