#!perl -w
use strict;
use Pod::Simple::HTMLBatch;

my @src = qw(site/docs site/cgi-bin/modules site/util .);
my $b = Pod::Simple::HTMLBatch->new; 
$b->batch_convert(\@src, shift);
