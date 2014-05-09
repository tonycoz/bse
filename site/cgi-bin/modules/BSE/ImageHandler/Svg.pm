package BSE::ImageHandler::Svg;
use strict;
use base 'BSE::ImageHandler::Img';
use BSE::Util::HTML;
use Carp qw(confess);

our $VERSION = "1.000";

sub _make_thumb_hash {
  my ($self, $geo_id, $im, $static, $abs_urls) = @_;

  my $cfg = $self->cfg;
  my $debug = $cfg->entry('debug', 'thumbnails', 0);

  $static ||= 0;

  $debug
    and print STDERR "_make_thumb_hash(..., $geo_id, $im->{src}, ..., $static)\n";

  $geo_id =~ /^[\w,]+$/
    or return ( undef, "* invalid geometry id *" );

  my $geometry = $cfg->entry('thumb geometries', $geo_id)
    or return ( undef, "* cannot find thumb geometry $geo_id *" );

  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or return ( undef, '* no thumbnail engine configured *' );

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);

  $debug
    and print STDERR "  Thumb class $thumbs_class\n";

  my $error;
  $thumbs->validate_geometry($geometry, \$error)
    or return ( undef, "* invalid geometry string: $error *" );

  my %im = map { $_ => $im->{$_} } $im->columns;

  @im{qw/width height type original/} = 
    $thumbs->thumb_dimensions_sized($geometry, @$im{qw/width height/});

  $im{image} = $im->src;

  if ($abs_urls && $im{image} !~ /^\w+:/) {
    $im{image} = $cfg->entryVar('site', 'url') . $im{image};
  }

  $im{src} = $im{image};

  return \%im;
}

1;

=head1 NAME

BSE::ImageHandler::Svg - handle "image" display for SVG

=head1 DESCRIPTION

This module provides display rendering and limited thumbnail rendering
for SVG content in the image manager.

=cut
