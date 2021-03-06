#!/usr/bin/perl -w
use strict;
use lib '../modules';
use CGI::Carp qw(fatalsToBrowser);
use BSE::WebUtil qw(refresh_to);
use BSE::Request;
use BSE::Permissions;

my $req = BSE::Request->new;

if (BSE::Permissions->check_logon($req)) {
  if ($req->user_can('bse_siteuser_export')) {
    my $cgi = $req->cgi;
    my $field = $cgi->param('field');
    my $min = $cgi->param('min');
    my $max = $cgi->param('max');
    do_dump($field, $min, $max);
  }
  else {
    refresh_to($req->url('menu', { m => 'Access denied' }));
  }
}
else {
  refresh_to($req->url('logon', { r => $ENV{SCRIPT_NAME} }));
}

sub do_dump {
  my ($field, $min, $max) = @_;

  my $dh = single BSE::DB;

  $field ||= 'id';
  grep $_ eq $field, qw/id userId/ or $field = 'id';

  my $sql;
  my @parms;
  if (defined $min and length $min) {
    if (defined $max and length $max) {
      $sql = "select * from bse_siteusers where $field >= ? and $field <= ?";
      @parms = ( $min, $max );
    }
    else {
      $sql = "select * from bse_siteusers where $field >= ?";
      @parms = ( $min );
    }
  }
  else {
    if (defined $max and length $max) {
      $sql = "select * from bse_siteusers where $field <= ?";
      @parms = ( $max );
    }
    else {
      $sql = 'select * from bse_siteusers';
    }
  }
  
  my $sth = $dh->{dbh}->prepare($sql)
    or die "Cannot prepare site_users select:", $DBI::errstr;
  
  $sth->execute(@parms)
    or die "Cannot execute site_users select:", $sth->errstr;
  
  print "Content-Type: application/octet-stream\n";
  print "Content-Disposition: attachement; filename=members.csv\n\n";
  
  print join(",",@{$sth->{NAME}}),"\r\n";
  while (my $row = $sth->fetchrow_arrayref) {
    print join(",", map { escape($_) } @$row),"\r\n";
  }
}
  
sub escape {
  my ($text) = @_;
  defined $text or $text = ''; # we may have NULLs
  return $text unless $text =~ /[",\n\r]/;
  $text =~ s/"/""/g;
  $text =~ tr/\n\r/ /;
  return qq!"$text"!
}
