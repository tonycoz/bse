#!/usr/bin/perl -w
use strict;
use lib '../modules';
use CGI::Carp qw(fatalsToBrowser);

use BSE::DB;

my $dh = single BSE::DB;

my $sth = $dh->{dbh}->prepare('select * from site_users')
  or die "Cannot prepare site_users select:", $DBI::errstr;

$sth->execute()
  or die "Cannot execute site_users select:", $sth->errstr;

print "Content-Type: application/octet-stream\n";
print "Content-Disposition: attachement; filename=members.csv\n\n";

print join(",",@{$sth->{NAME}}),"\r\n";
while (my $row = $sth->fetchrow_arrayref) {
  print join(",", map { escape($_) } @$row),"\r\n";
}

sub escape {
  my ($text) = @_;
  defined $text or $text = ''; # we may have NULLs
  return $text unless $text =~ /[",]/;
  $text =~ s/"/""/g;
  return qq!"$text"!
}
