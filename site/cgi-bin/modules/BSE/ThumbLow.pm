package BSE::ThumbLow;
use strict;
use DevHelp::HTML;

sub _thumbimage_low {
  my ($self, $geo_id, $im, $field, $cfg, $static) = @_;

  return $im->thumb
    (
     geo => $geo_id,
     field => $field,
     cfg => $cfg,
     static => $static,
    );
}

1;
