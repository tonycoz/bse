package BSE::DummyArticle;
use base 'BSE::TB::SiteCommon';
use Articles;

our $VERSION = "1.000";

sub images {
  return;
}

sub files {
  return;
}

{
  for my $name (Article->columns) {
    eval "sub $name { \$_[0]{$name} }";
  }
}

sub restricted_method {
  return 0;
}

sub section {
  $_[0];
}

sub is_descendant_of {
  0;
}

sub parent {
  return;
}

sub is_dynamic {
  1;
}

sub is_step_ancestor {
  0;
}

sub menu_ancestors {
  return;
}

1;
