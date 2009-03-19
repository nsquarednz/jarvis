#NOT FOR RUNNING AS CGI
#
# Description:  Functions for dealing with login and user authentication.
#
#               This is a database module that reads a single table
#               that contains a username and password field, and checks that
#               the supplied pair exists in that table.
###############################################################################
#
use CGI;

use strict;
use warnings;

use Jarvis::Error;

package Jarvis::Login::Database;

###############################################################################
# Public Functions
###############################################################################

################################################################################
# Determines if we are "logged in".  In this case we look at CGI variables
# for the existing user/pass.  We validate this by checking a table in the 
# currently open database.  The user and pass columns are both within this same
# table.
#
# We require config of the form...
#  
#  <app name="spiderfan">
#    <login page="login.html" module="Jarvis::Login::Database">
#      <params table="staff" user="username" pass="password"/>
#    </login>
#    ...
#
# Params:
#       $args{'cgi'} - CGI object
#       $args{'dbh'} - DBI object
#
# Returns:
#       ($error_string or "", $username or "" [, group1, group2, group3...])
################################################################################
#
sub Jarvis::Login::Check {
    my (%args) = @_;

    my $username = $args{'cgi'}->param('username');
    my $password = $args{'cgi'}->param('password');

    # No info?
    if (! ((defined $username) && ($username ne ""))) {
        return ("No username supplied.");

    } elsif (! ((defined $password) && ($password ne ""))) {
        return ("No password supplied.");
    }

    my $query = "SELECT rank, password FROM staff WHERE name = ?";
    my $sth = $args{'dbh'}->prepare ($query) 
            || &Jarvis::Error::MyDie ("Couldn't prepare statement '$query': " . $args{'dbh'}->errstr, %args);
        
    $sth->execute ($username) 
            || &Jarvis::Error::MyDie ("Couldn't execute statement '$query': " . $args{'dbh'}->errstr, %args); 
            
    my $result_aref = $sth->fetchall_arrayref({});
    if ((scalar @$result_aref) < 1) {
        return ("User '$username' not known.");
    }
    if ((scalar @$result_aref) > 1) {
        return ("User '$username' not unique (" . (scalar @$result_aref). ").");         # Should never happen.
    }
    my $result_href = $$result_aref[0];
    my $rank = $$result_href{'rank'} || '';
    my $stored_password = $$result_href{'password'} || '';

    if ($stored_password eq '') {
        return ("No password stored for user '$username'.");
    }
    if ($stored_password ne $password) {
        return ("Incorrect password for user '$username'.");
    }
    my @groups = ();
    if ($rank eq 'A') {
        push (@groups, "admin");

    } elsif (($rank eq 'S') || ($rank eq 'L')) {
        push (@groups, "staff");
        
    } elsif ($rank eq 'F') {
        return ("User '$username' is marked as Former.");

    } else {
        return ("User '$username' has unknown rank '$rank'.");
    }
        
    # Guess it worked?
    return ("", $username, join (",", @groups));
}

1;
