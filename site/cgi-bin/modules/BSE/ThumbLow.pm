package BSE::ThumbLow;
use strict;

our $VERSION = "1.001";

sub _thumbimage_low {
  my ($self, $geo_id, $im, $field, $cfg, $static) = @_;

  return $im->thumb
    (
     geo => $geo_id,
     field => $field,
     cfg => $cfg,
     static => $static,
     abs_urls => $self->abs_image_urls,
    );
}

sub abs_image_urls {
  0;
}

1;
