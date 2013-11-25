package BSE::ThumbCommon;
use strict;
use Carp ();

our $VERSION = "1.001";

=head1 NAME

BSE::ThumbCommon - behaviour for images with thumbnails.

=head1 SYNOPSIS

  my $thumb = $image->thumb(...)

=head1 DESCRIPTION

=over

=cut

# common code between article images and BSE::TB::File

sub _handler_object {
  my ($im, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $module = "BSE::ImageHandler::" . ucfirst($im->ftype);
  (my $file = $module . ".pm") =~ s(::)(/)g;
  require $file;
  my $handler = $module->new(cfg => $cfg);
}

=item thumb(...)

Calls the thumb method on the image handler object.

Parameters:

=over

=item *

C<geo> - thumbnail geometry

=item *

C<field> - field to return, if any.  This can be C<object> to return a
hash of image information.  Fields are otherwise returned HTML
encoded.

=item *

C<geo> - thumbnail geometry (required)

=item *

C<static> - set to true to return a URL to a pregenerated thumbnail
image.

=back

Returns HTML unless C<field> is supplied.

=cut

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

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
