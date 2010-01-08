package BSE::TB::Site;
use strict;
use base qw(BSE::TB::SiteCommon);

# like an article, but doesn't exist in the database

sub new {
  my ($class) = @_;

  return bless
    {
     id => -1,
     title => "Your site",
     generator => 'Generate::Article',
     parentid=>0,
     level => 0,
     body => '',
     flags => '',
     listed => 0,
    }, $class;
}

sub id {
  -1;
}

1;
