package BSE::Handler::Page;
use strict;
use base qw'BSE::Handler::Base BSE::UI::Page';
use Generate::Article;
use BSE::Template;
use SiteUsers;
use BSE::CfgInfo;
use BSE::TB::SiteUserGroups;
use BSE::Util::DynamicTags;

sub handler {
  my ($r) = @_;

  __PACKAGE__->SUPER::handler($r);
}

1;
