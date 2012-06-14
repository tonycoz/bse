package BSE::TB::TagCategoryDep;
use strict;
use base 'Squirrel::Row';

our $VERSION = "1.000";

sub columns {
  qw(id cat_id depname);
}

sub table { 'bse_tag_category_deps' }

sub json_data {
  my ($self) = @_;

  return $self->data_only;
}

1;
