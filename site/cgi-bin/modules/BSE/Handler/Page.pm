package BSE::Handler::Page;
use strict;
use base qw'BSE::Handler::Base BSE::UI::Page';
use BSE::Generate::Article;
use BSE::Template;
use BSE::TB::SiteUsers;
use BSE::CfgInfo;
use BSE::TB::SiteUserGroups;
use BSE::Util::DynamicTags;
use BSE::Dynamic::Article;
use BSE::Dynamic::Product;
use BSE::Dynamic::Catalog;
use BSE::Dynamic::Seminar;

our $VERSION = "1.002";

sub handler {
  my ($r) = @_;

  __PACKAGE__->SUPER::handler($r);
}

1;
