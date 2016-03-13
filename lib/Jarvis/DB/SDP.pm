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
#       $root - XML object of successful response "root".
################################################################################
#
sub fetchall {
    
    my ($self, $jconfig, $mdx) = @_;
    
    &Jarvis::Error::debug ($jconfig, "Performing Execute request to SSAS DataPump.");
    
    my @property_list = ();
    if ($self->{'parameters'}->{'catalog'}) {
        push (@property_list,
            SOAP::Data->value(
                SOAP::Data->name('Catalog')->value($self->{'parameters'}->{'catalog'}),
            )
        );
    };
                    
    my $soap = $self->{'soap'};
    my $rxml = $soap->call('Execute',         
        SOAP::Data->name('Command')->value(
            \SOAP::Data->value(
                SOAP::Data->name('Statement')->type('string')->value($mdx)
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
    
    return $response->{'soap:Envelope'}->{'soap:Body'}->{'ExecuteResponse'}->{'return'}->{'root'} 
        || die "Missing ExecuteResponse/return/root in SDP response.";
}
    
################################################################################
# Makes the specified MDX request, and converts to similar structure to DBI.
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return 
# object.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $mdx - Query to execute
#       $row_label - What name to use to store our row labels.
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
################################################################################
#
sub fetchall_arrayref {
    my ($self, $jconfig, $mdx, $row_label) = @_;
    
    # Get the raw data.
    my $root = $self->fetchall ($jconfig, $mdx);
    
    # Check for errors.
    &Jarvis::Error::dump ($jconfig, $root->data); 
    if ($root->{'Exception'}) {
        my $code = $root->{'Messages'}->{'Error'}->{'ErrorCode'} || '???';
        my $description  = $root->{'Messages'}->{'Error'}->{'Description'} || '???';
        die "An MDX error $code occured: $description";
    }
    
    # Otherwise, assume we have data.
    &Jarvis::Error::debug ($jconfig, "Converting 2D MDX result to Array of tuples.");

    # Now the fun bit.  Convert the deep complicated structure into 2D tuple array like DBI would.
    my @axis_names = grep { $_ ne 'SlicerAxis' } map { $_->{'name'}->content } $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}('@');
    foreach my $axis_name (@axis_names) {
        &Jarvis::Error::debug ($jconfig, "Axis: $axis_name");        
    }
    (scalar @axis_names == 2) || die "Require exactly two (non-Slice) Axes for 2D tuple encoding.  Got " . (scalar @axis_names) . ".";

    # What are the names for the column/row axes?    
    my $column_axis_label = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[0]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis0 Name";
    my $row_axis_label = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[1]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis1 Name";
    &Jarvis::Error::debug ($jconfig, "Column Axis Label = $column_axis_label");
    &Jarvis::Error::debug ($jconfig, "Row Axis Label = $row_axis_label");
    
    # What are the tuple names?
    ($root->{'Axes'}->{'Axis'}[0]->{'name'}->content eq 'Axis0') || die "Inconsistent Axis0 Name";
    ($root->{'Axes'}->{'Axis'}[1]->{'name'}->content eq 'Axis1') || die "Inconsistent Axis1 Name";

    my @column_names = map { my $x = $_->{'Member'}->{'Caption'}->content; $x; } $root->{'Axes'}->{'Axis'}[0]->{'Tuples'}{'Tuple'}('@');

    my $num_columns = scalar @column_names;
    
    my @row_names = map { my $x = $_->{'Member'}->{'Caption'}->content; $x; } $root->{'Axes'}->{'Axis'}[1]->{'Tuples'}{'Tuple'}('@');
    my $num_rows = scalar @row_names;    
    
    # Pre-fill the rows.
    &Jarvis::Error::debug ($jconfig, "Have $num_columns columns, $num_rows rows.");
    my @rows = ();
    foreach my $i (0 .. ($num_rows - 1)) {
        if ($row_label) {
            push (@rows, {$row_label => $row_names[$i]});
            
        } else {
            push (@rows, '');
        }
    }
    
    # Now the cell data
    foreach my $cell ($root->{'CellData'}->{'Cell'}('@')) {
        my $ordinal = $cell->{'CellOrdinal'}->content;
        my $value = $cell->{'Value'}->content;
        my $column = $ordinal % $num_columns;
        my $row = ($ordinal - $column) / $num_columns;
        my $column_name = $column_names[$column];
        $rows[$row]->{$column_name} = $value; 
    }

    # Finally put the row label column at the start of the column list.
    if ($row_label) {
        @column_names = ($row_label, @column_names);
    }

    return (\@rows, \@column_names);
}

################################################################################
# Makes the specified MDX request, and returns an 3D nested hash.  
#
# This function only processes a single dataset.  The parent method may invoke
# us multiple times for a single request, and combine into a single return 
# object.
#
# Params:
#       $jconfig - Jarvis::Config object
#       $mdx - Query to execute
#       $row_label - What name to use to store our row labels.
#
# Returns:
#       $rows_aref - Array of tuple data returned.
#       $column_names_aref - Array of tuple column names, if available.
################################################################################
#
sub fetchall_hashref_3d {
    my ($self, $jconfig, $mdx, $row_label) = @_;
    
    # Get the raw data.
    my $root = $self->fetchall ($jconfig, $mdx);
    
    &Jarvis::Error::debug ($jconfig, "Converting 3D MDX result to Array of nested tuples.");

    # Now the fun bit.  Convert the deep complicated structure into 2D tuple array like DBI would.
    my @axis_names = grep { $_ ne 'SlicerAxis' } map { $_->{'name'}->content } $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}('@');
    foreach my $axis_name (@axis_names) {
        &Jarvis::Error::debug ($jconfig, "Axis: $axis_name");        
    }
    (scalar @axis_names == 3) || die "Require exactly three (non-Slice) Axes for 3D tuple encoding.  Got " . (scalar @axis_names) . ".";

    # What are the names for the column/row axes?    
    my $column_axis_label = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[0]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis0 Name";
    my $row_axis_label = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[1]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis1 Name";
    my $page_axis_label = $root->{'OlapInfo'}->{'AxesInfo'}->{'AxisInfo'}[2]->{'HierarchyInfo'}->{'name'}->content || "Unknown Axis2 Name";
    &Jarvis::Error::debug ($jconfig, "Column Axis Label = $column_axis_label");
    &Jarvis::Error::debug ($jconfig, "Row Axis Label = $row_axis_label");
    &Jarvis::Error::debug ($jconfig, "Page Axis Label = $page_axis_label");
    
    # What are the tuple names?
    ($root->{'Axes'}->{'Axis'}[0]->{'name'}->content eq 'Axis0') || die "Inconsistent Axis0 Name";
    ($root->{'Axes'}->{'Axis'}[1]->{'name'}->content eq 'Axis1') || die "Inconsistent Axis1 Name";
    ($root->{'Axes'}->{'Axis'}[2]->{'name'}->content eq 'Axis2') || die "Inconsistent Axis2 Name";
    
    my @column_names = map { $_->{'Member'}->{'Caption'}->content } $root->{'Axes'}->{'Axis'}[0]->{'Tuples'}{'Tuple'}('@');
    my $num_columns = scalar @column_names;
    foreach my $column (@column_names) {
        &Jarvis::Error::dump ($jconfig, "Column: " . $column);        
    }
    
    my @row_names = map { $_->{'Member'}->{'Caption'}->content } $root->{'Axes'}->{'Axis'}[1]->{'Tuples'}{'Tuple'}('@');
    my $num_rows = scalar @row_names;    
    foreach my $row (@row_names) {
        &Jarvis::Error::dump ($jconfig, "Row: " . $row);        
    }

    my @page_names = map { $_->{'Member'}->{'Caption'}->content } $root->{'Axes'}->{'Axis'}[2]->{'Tuples'}{'Tuple'}('@');
    my $num_pages = scalar @page_names;    
    foreach my $page (@page_names) {
        &Jarvis::Error::dump ($jconfig, "Page: " . $page);        
    }
    
    # Pre-fill the rows.
    &Jarvis::Error::debug ($jconfig, "Have $num_columns columns, $num_rows rows, $num_pages pages.");
    
    # Now the cell data
    my %data = ();
    foreach my $cell ($root->{'CellData'}->{'Cell'}('@')) {
        my $ordinal = $cell->{'CellOrdinal'}->content;
        my $value = $cell->{'Value'}->content;
        my $column = $ordinal % $num_columns;
        $ordinal = ($ordinal - $column) / $num_columns;

        my $row = $ordinal % $num_rows;
        $ordinal = ($ordinal - $row) / $num_rows;
        
        my $page = $ordinal;
        
        &Jarvis::Error::debug ($jconfig, "Index $ordinal -> C/R/P = $column, $row, $page.");
        
        my $column_name = $column_names[$column];
        my $row_name = $row_names[$row];
        my $page_name = $page_names[$page];
        $data{$page_name}{$row_name}{$column_name} = $value; 
    }

    return (\%data);
}

1;
