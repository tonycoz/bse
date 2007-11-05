package BSE::Formatter::Subscription;
use strict;
use base 'BSE::Formatter';

# eventually this will attach the image
sub image_url {
  my ($self, $im) = @_;

  my $url = $self->SUPER::image_url($im);
  
  $self->{gen}{cfg}->entryVar('site', 'url') . $url;
}

1;