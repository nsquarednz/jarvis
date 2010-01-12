use strict;
use warnings;

use Digest::MD5 qw (md5 md5_hex);

sub plugin::SetPassword::do {
    my ($jconfig, $rest_args, %args) = @_;

    # Check we are admin.
    &Jarvis::Error::log ($jconfig, "Setting password for user '" . $jconfig->{'username'} . "'.");
    my @groups = split (',', $jconfig->{'group_list'});
    grep { $_ =~ m/^admins$/ } @groups || die "Only admins may reset passwords.";

    # Check required args.
    my $username = $jconfig->{'cgi'}->param('username') || die "Missing CGI parameter 'username'";
    my $password = $jconfig->{'cgi'}->param('password') || '';
    &Jarvis::Error::log ($jconfig, "Setting for username '$username'.  Password = " . ($password ? "'$password'" : "NULL") . ".");

    # Choose a random two character salt.
    my $salt = join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];

    # Create the string to store in the database.  Empty password is stored as NULL.
    my $encrypted = ((defined $password) && ($password ne '')) ? ($salt . &md5_hex ($salt . $password)) : undef;

    &Jarvis::Error::log ($jconfig, "Using salt '$salt'.  Encrypted = " . ($encrypted ? "'$encrypted'" : "NULL") . ".");

    my $dbh = &Jarvis::DB::handle ($jconfig);
    my $rv = $dbh->do ('UPDATE users SET password = ? WHERE name = ?', undef, $encrypted, $username);
    $dbh->errstr && die "Database error performing password update: " . $dbh->errstr;
    $rv || die "Password update impossible.  No such username '$username'";

    return 'Success';
}

1;
