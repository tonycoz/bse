#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.15:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Constants qw($UN $PW $DSN $SHOP_FROM $DATA_EMAIL);
use BSE::Mail;
use BSE::Cfg;
use DevHelp::HTML;
my $cfg = BSE::Cfg->new;

my $email = $cfg->entryIfVar('datadump', 'to') || $DATA_EMAIL;
my $from = $cfg->entryIfVar('datadump', 'from') || $SHOP_FROM;
my $urlbase = $cfg->entryVar('site', 'url');
my $opts = '-t';
my $dumper = $cfg->entryIfVar('datadump', 'mysqldump') || 'mysqldump';
$|=1;
print "Content-Type: text/html\n\n";

unless ($email) {
  print "Configuration Error: You need to set the <b>to</b> key in the [datadump] section of the config file, or \$DATA_EMAIL in Constants.pm";
  exit;
}
unless ($from) {
  print "Configuration Error: You need to set the <b>from</b> key in the [datadump] section of the config file, or \$SHOP_FROM in Constants.pm";
  exit;
}

my $user = $UN;
my $pass = $PW;
my $data;
my $host;
my $port;
if ($DSN =~ /^dbi:mysql:(\w+)$/i) {
  $data = $1;
}
elsif ($DSN =~ /^dbi:mysql:(.*)$/i) {
  my @entries = split /;/, $1;
  for my $entry (@entries) {
    if ($entry =~ /^hostname=(.+)$/i) {
      $host = $1;
    }
    elsif ($entry =~ /^database=(.+)$/i) {
      $data = $1;
    }
    elsif ($entry =~ /^port=(.+)$/i) {
      $port = $1;
    }
  }
  unless ($data) {
    print "Sorry, could not find database in ",escape_html($DSN),"<br>\n";
    exit;
  }
}
else {
  print "Sorry, this doesn't appear to be a mysql database<br>\n";
  exit;
}

for ($user, $pass, $data) {
  s/(["\\`\$])/\\$1/;
}
my $cmd = qq!$dumper !;
$cmd .= qq!-P$port ! if $port;
$cmd .= qq!-h$host ! if $host;
$cmd .= qq!"-u$user" "-p$pass" "$data"!;
open DUMP, "$cmd 2>&1 |"
  or do { print "Cannot open mysqldump: $!\n"; exit };

my $boundary = "============_".time."_==========";
my $headers = <<EOS;
Content-Type: multipart/mixed;
    boundary="$boundary"
MIME-Version: 1.0
EOS

my $body = <<EOS;

This is a multipart message in MIME format

--$boundary
Content-Type: text/plain

This message contains a database dump of the BSE site $urlbase.

If you did not request this dump you may want to change the 
administration password for your site.

--$boundary
Content-Type: text/plain
Content-Disposition: attachment; filename=bsedump.txt

EOS
while (<DUMP>) {
  $body .= $_;
}

$body .= <<EOS;
--$boundary--

EOS

my $mailer = BSE::Mail->new(cfg=>$cfg);
$mailer->send(to=>$email,
	      from=>$from,
	      headers=>$headers,
	      body=>$body,
	      subject=>$cfg->entry('datadump') || "Data dump")
  or print "Error sending email: ",escape_html($mailer->errstr),"<br>\n";
unless (close DUMP) {
  print "There may have been a problem retrieving the dump, please check the error log<br>";
}
print "Database dump for $urlbase sent to $email\n";

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
