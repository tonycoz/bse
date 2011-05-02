package BSE::TB::Images;
use strict;
use Squirrel::Table;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table);
use BSE::TB::Image;

our $VERSION = "1.001";

sub rowClass {
  return 'BSE::TB::Image';
}

sub image_storages {
  return map [ $_->{image}, $_->{storage}, $_ ], BSE::TB::Images->all;
}

sub image_dir {
  require BSE::CfgInfo;

  return BSE::CfgInfo::cfg_image_dir(BSE::Cfg->single);
}

1;
