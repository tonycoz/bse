package BSE::DummyArticle;
use strict;
use base 'BSE::TB::SiteCommon';
use base 'BSE::FormatterBase';
use BSE::TB::Articles;
use base 'BSE::MetaOwnerBase';

our $VERSION = "1.007";

sub images {
  return;
}

sub files {
  return;
}

{
  for my $name (BSE::TB::Article->columns) {
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

sub should_index {
  1;
}

sub tags {
  ();
}

sub has_tags {
  0;
}

sub meta_owner_type {
  'bse_article';
}

sub meta_meta_cfg_section {
  "global article metadata";
}

sub meta_meta_cfg_prefix {
  "article metadata";
}

sub metafields {
  my ($self, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my %metanames = map { $_ => 1 } $self->metanames;

  require BSE::ArticleMetaMeta;
  my @fields = grep $metanames{$_->name} || $_->cond($self), BSE::ArticleMetaMeta->all_metametadata($cfg);

  return ( @fields );
}


1;
