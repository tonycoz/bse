#!/usr/bin/perl
use lib '../modules';
use Constants qw($UN $PW $DB $SHOP_SENDMAIL $SHOP_FROM $URLBASE $DATA_EMAIL
                 $MYSQLDUMP);

my $email = $DATA_EMAIL;
my $opts = '-t';
my $dumper = $MYSQLDUMP;
$|=1;
print "Content-Type: text/plain\n\n";
my $user = $UN;
my $pass = $PW;
my $data = $DB;
for ($user, $pass, $data) {
  s/(["\\`\$])/\\$1/;
}
my $cmd = qq!$dumper "-u$user" "-p$pass" "$data"!;
open DUMP, "$cmd 2>&1 |"
  or do { print "Cannot open mysqldump: $!\n"; exit };

# redirect to /dev/null so that the server sees STDOUT close
# as soon as possible
open EMAIL, "| $SHOP_SENDMAIL $opts >/dev/null"
  or do { print "Cannot open sendmail: $!\n"; exit };
my $boundary = "============_".time."_==========";
print EMAIL <<EOS;
To: $email
From: $SHOP_FROM
Content-Type: multipart/mixed;
    boundary="$boundary"
MIME-Version: 1.0

This is a multipart message in MIME format

--$boundary
Content-Type: text/plain

This message contains a database dump of the BSE site $URLBASE.

If you did not request this dump you may want to change the 
administration password for your site.

--$boundary
Content-Type: text/plain
Content-Disposition: attachment; filename=bsedump.txt

EOS
while (<DUMP>) {
print EMAIL;
}
print EMAIL <<EOS;
--$boundary--

EOS
unless (close EMAIL) {
  print "There may have been a problem sending the email, please check the error log\n";
}
unless (close DUMP) {
  print "There may have been a problem retrieving the dump, please check the error log\n";
}
print "Database dump for $URLBASE sent to $email\n";

__END__

=head1 NAME

  datadump.pl - dumps a mysql database and emails the result

=head1 SYNOPSIS

 (run as a CGI script)

=head1 DESCRIPTION

Emails a copy of the results of mysqldump as an attachment to the user
specified by $DATA_EMAIL in Constants.pm.

This is pretty quick and dirty code, so YMMV.  Please report bugs
anyway.

=head1 AUTHOR

Tony Cook <tony@develop-help.com> at the prodding of Adrian Oldham.

=cut
