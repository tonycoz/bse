package BSE::TB::Images;
use strict;
use Squirrel::Table;
require BSE::TB::TagOwners;
use vars qw(@ISA $VERSION);
@ISA = qw(Squirrel::Table BSE::TB::TagOwners);
use BSE::TB::Image;

our $VERSION = "1.004";

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

=item base_uri

Return the base URI for images stored in the image_dir().

Traditionally C</images/>, but it's meant to be configurable.

This includes a trailing C</> unlike L<BSE::CfgInfo/cfg_image_uri()>.

=cut

sub base_uri {
  require BSE::CfgInfo;
  return BSE::CfgInfo::cfg_image_uri() . "/";
}

=item get_ftype($is_type)

Translate an Image::Size file type into a value for the ftype
attribute.

=cut

sub get_ftype {
  my ($self, $type) = @_;

  if ($type eq 'CWS' || $type eq 'SWF') {
    return "flash";
  }

  return "img";
}

=item storage_manager

Return the images storage manager.

=cut

sub storage_manager {
  require BSE::StorageMgr::Images;

  return BSE::StorageMgr::Images->new(cfg => BSE::Cfg->single);
}

1;
