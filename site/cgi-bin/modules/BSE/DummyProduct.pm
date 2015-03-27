package BSE::DummyProduct;
use strict;
use BSE::DummyArticle;
our @ISA = qw(BSE::DummyArticle);
use BSE::TB::Products;

our $VERSION = "1.000";

{
  my %fields;
  @fields{BSE::TB::Product->columns} = ();
  delete @fields{BSE::TB::Article->columns};
  for my $name (keys %fields) {
    eval "sub $name { \$_[0]{$name} }";
  }
}


sub prices {}

1;
