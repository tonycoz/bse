#!/usr/bin/perl -w 
#-d:ptkdb
#BEGIN { $ENV{DISPLAY}="192.168.32.97:0.0"; };
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use CGI qw(:standard);
use BSE::Cfg;
use vars qw($VERSION);
$VERSION = 1.02;

my $cfg = BSE::Cfg->new;
my $urlbase = $cfg->entryVar('site', 'url');

my $refreshto = param('refreshto') || '/admin/';
# each entry of @kids is an arrayref containing the article
# to get sort data from, the actual object, and the field in the actual
# object containing the display order value
my @kids;
my %kids;
my $parentid = param('parentid');
my $stepparent = param('stepparent');
my $stepchild = param('stepchild');
if ($parentid) {
  $parentid += 0;
  @kids = map [$_, $_, 'displayOrder' ], Articles->getBy(parentid=>$parentid);
}
elsif ($stepparent) {
  require 'OtherParents.pm';

  my $parent = Articles->getByPkey($stepparent);
  if ($parent) {
    my @otherlinks = OtherParents->getBy(parentId=>$stepparent);
    my @normalkids = Articles->listedChildren($stepparent);
    my @stepkids = $parent->stepkids;
    my %stepkids = map { $_->{id}, $_ } @stepkids;
    @kids = (
	     map([ $_, $_, 'displayOrder' ], @normalkids),
	     map([ $stepkids{$_->{childId}}, $_, 'parentDisplayOrder' ],
		 @otherlinks),
	    );
  }
}
elsif ($stepchild) {
  require 'OtherParents.pm';

  my $child = Articles->getByPkey($stepchild);
  if ($child) {
    my @otherlinks = OtherParents->getBy(childId=>$stepchild);
    my @stepparents = map Articles->getByPkey($_->{parentId}), @otherlinks;
    my %stepparents = map { $_->{id}, $_ } @stepparents;
    @kids = (
	     map([ $stepparents{$_->{parentId}}, $_, 'childDisplayOrder' ],
		 @otherlinks),
	    );
  }
}


my @order = sort { $b <=> $a } map $_->[1]{$_->[2]}, @kids;
my $sort = param('sort') || 'current';
my $reverse = param('reverse');

my $code;
if ($sort eq 'title') {
  $code = sub { lc($a->[0]{title}) cmp lc($b->[0]{title}) };
}
elsif ($sort eq 'date') {
  $code = sub { $a->[0]{lastModified} cmp $b->[0]{lastModified} };
}
elsif ($sort eq 'current') {
  $code = sub { $b->[1]{$b->[2]} <=> $a->[1]{$a->[2]} };
}
if ($reverse) {
  my $temp = $code;
  $code = sub { -$temp->() };
}
if ($code) {
  @kids = sort $code @kids;
  for my $i (0..$#kids) {
    my $kid = $kids[$i];
    $kid->[1]{$kid->[2]} = $order[$i];
    $kid->[1]->save();
  }
}

print "Refresh: 0; url=\"$urlbase$refreshto\"\n";
print "Content-Type: text/html\n\n<html></html>\n";

=head1 NAME

reorder.pl - reorder the article siblings, given their parent id

=head1 SYNOPSIS

  <html>...
  <a href="/cgi-bin/admin/reorder.pl?parentid=...&sort=...>Order</a>
  ...</html>

=head1 DESCRIPTION

Sorts the articles that are either the children, step children or step
parents of a given article depending on the value of the I<sort> and
I<reverse> parameters.  Once the sort is complete a refresh is
generated to the local url in I<refreshto>.

One of the I<parentid>, I<stepparent>, or I<stepchild> parameters
needs to be defined, otherwise no sort is performed.

=over

=item parentid

The parentid of the articles to be sorted.  This can be C<-1> to sort
sections.  If there are no articles that have this as their
I<parentid> then zero articles are harmlessly sorted.

=item stepparent

the step parent is of articles to be sorted.  This will sort both the
normal children and stepchildren of the given article.  This cannot be
C<-1>.

=item stepchild

the step child of the articles to be sorted (currently must be a
product).  This will sort only the step parents, and will not include
the normal parent.

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

