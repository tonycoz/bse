package BSE::ThumbCommon;
use strict;

# common code between article images and BSE::TB::File

sub _handler_object {
  my ($im, $cfg) = @_;

  my $module = "BSE::ImageHandler::" . ucfirst($im->ftype);
  (my $file = $module . ".pm") =~ s(::)(/)g;
  require $file;
  my $handler = $module->new(cfg => $cfg);
}

sub thumb {
  my ($im, %opts) = @_;

  my $cfg = delete $opts{cfg}
    or confess "Missing cfg parameter";

  my $handler = $im->_handler_object($cfg);

  return $handler->thumb
    (
     image => $im,
     %opts,
    );
}

1;
