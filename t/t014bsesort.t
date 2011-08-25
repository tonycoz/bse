#!perl -w
use strict;
use Test::More tests => 3;

BEGIN { use_ok("BSE::Sort", "bse_sort"); }

{
  my $a100 = { a => 100, b => 3 };
  my $a2 = { a => 2, b => 2 };
  my $a30 = { a => 30, b => 4 };

  my @in = ( $a2, $a100, $a30 );
  my %types = qw(a n b n);

  {
    my @out = bse_sort(\%types, "sort=a", @in);
    is_deeply(\@out, [ $a2, $a30, $a100 ], "check simple numeric sort");
  }
  {
    my @out = bse_sort(\%types, "filter= b >= 3", @in);
    is_deeply(\@out, [ $a100, $a30 ], "check simple filtering");
  }
}
