#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use CGI qw(:standard);
use Constants qw($URLBASE);
use vars qw($VERSION);
$VERSION = 1.01;

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

=head1 NAME

reorder.pl - reorder the article siblings, given their parent id

=head1 SYNOPSIS

  <html>...
  <a href="/cgi-bin/admin/reorder.pl?parentid=...&sort=...>Order</a>
  ...</html>

=head1 DESCRIPTION

Sorts the articles under a given I<parentid> depending on the value of
the I<sort> and I<reverse> parameters.  Once the sort is complete a
refresh is generated to the local url in I<refreshto>.

The parameters are:

=over

=item parentid

The parentid of the articles to be sorted.  If this is missing no sort
is performed.  This can be C<-1> to sort sections.  If there are no
articles that have this as their I<parentid> then zero articles are
harmlessly sorted.

=item sort

The field to sort by:

=over

=item title

Sort by the title.

=item date

Sort by the lastModified field.  Note: since I<lastModified> is a date
field articles modified on the same date may not sort the way you
expect.

=item current

Trivial sort to the same order.  This is intended to be used with
I<reverse>.

=back

=item reverse

If this is true then the sort is reversed.

=item refreshto

After the articles are sorted, a refresh is generated to I<refreshto>
on $URLBASE.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

