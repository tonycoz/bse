package BSE::ImageSize;
use strict;
use Image::Size ();
use Fcntl ':seek';

our $VERSION = "1.000";

use Exporter 'import';
use Scalar::Util qw(reftype);

our @EXPORT_OK = qw(imgsize);

=head1 NAME

BSE::ImageSize - wrapper around Image::Size, adds SVG support

=head1 SYNOPSIS

  use BSE::ImageSize "imgsize";
  my ($width, $height, $type) = imgsize($fh);
  my ($width, $height, $type) = imgsize($filename);
  my ($width, $height, $type) = imgsize(\$buf);

=head1 DESCRIPTION

Retrieve the size of the given image file.

On error, returns $width and $height as undef and sets $type to the
error.

=cut

sub imgsize {
  my ($fh) = @_;

  my ($width, $height, $type) = Image::Size::imgsize($fh);

  unless (defined $width) {
    my $info = _parse_svg($fh);
    if (ref $fh && reftype $fh ne "SCALAR") {
      seek $fh, 0, SEEK_SET;
    }
    unless ($info->{error}) {
      ($width, $height, $type) = @{$info}{qw(width height file_type)};
    }
  }

  return ( $width, $height, $type );
}

sub _parse_svg {
  my ($file) = @_;

  require XML::Parser;

  my $io;
  if (ref $file) {
    if (reftype $file eq "SCALAR") {
      # IO::Scalar
      $io = $$file;
    }
    else {
      $io = $file;
      binmode $io;
    }
  }
  else {
    open $io, "<", $file;
    binmode $file;
  }

  my ($width, $height, $vb);
  my $parser = XML::Parser->new
    (
     Handlers =>
     {
      Start => sub {
	my ($self, $elem, %attr) = @_;

	if ($elem =~ /\bsvg$/) {
	  $width = $attr{width};
	  $height = $attr{height};
	  $vb = $attr{viewBox};
	  $self->finish;
	}
      },
     },
    );
  eval { $parser->parse($io) }
    or return;

  SKIP:
  {
    $width && $height
      or last SKIP;
    $width =~ /^(\d+)\s*(px)?$/
      or last SKIP;
    $width = $1;
    $height =~ /^(\d+)\s*(px)?$/
      or last SKIP;
    $height = $1;
    return +{ width => $width, height => $height, file_type => "SVG" };
  }

  $vb or return;

  ( undef, undef, $width, $height) = split /[\s,]/, $vb;
  $width && $height
    or return;

  return +{ width => $width, height => $height, file_type => "SVG" };
}

1;

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

