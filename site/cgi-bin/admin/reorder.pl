#!/usr/bin/perl -w
use strict;
use lib '../modules';
use Articles;
use CGI qw(:standard);
use Constants qw($URLBASE);

my $parentid = param('parentid');
my $refreshto = param('refreshto') || '/admin/';
if ($parentid) {
  $parentid += 0;
  my @kids = Articles->getBy(parentid=>$parentid);
  my @order = sort { $b <=> $a } map $_->{displayOrder}, @kids;
  my $sort = param('sort') || 'current';
  my $reverse = param('reverse');

  my $code;
  if ($sort eq 'title') {
    $code = sub { lc($a->{title}) cmp lc($b->{title}) };
  }
  elsif ($sort eq 'date') {
    $code = sub { $a->{lastModified} cmp $b->{lastModified} };
  }
  elsif ($sort eq 'current') {
    $code = sub { $b->{displayOrder} <=> $a->{displayOrder} };
  }
  if ($reverse) {
    my $temp = $code;
    $code = sub { -$temp->() };
  }
  if ($code) {
    @kids = sort $code @kids;
    for my $i (0..$#kids) {
      $kids[$i]{displayOrder} = $order[$i];
      $kids[$i]->save();
    }
  }
}

print "Refresh: 0; url=\"$URLBASE$refreshto\"\n";
print "Content-Type: text/html\n\n<html></html>\n";
