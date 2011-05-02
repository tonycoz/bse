package BSE::ThumbCommon;
use strict;
use Carp ();

our $VERSION = "1.000";

# common code between article images and BSE::TB::File

sub _handler_object {
  my ($im, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $module = "BSE::ImageHandler::" . ucfirst($im->ftype);
  (my $file = $module . ".pm") =~ s(::)(/)g;
  require $file;
  my $handler = $module->new(cfg => $cfg);
}

sub thumb {
  my ($im, %opts) = @_;

  my $cfg = delete $opts{cfg};

  my $handler = $im->_handler_object($cfg);

  return $handler->thumb
    (
     image => $im,
     %opts,
    );
}

1;
