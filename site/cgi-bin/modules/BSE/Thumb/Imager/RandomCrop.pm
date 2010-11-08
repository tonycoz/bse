package BSE::Thumb::Imager::RandomCrop;
use strict;
use base 'BSE::Thumb::Imager::Handler';

our $VERSION = "1.000";

sub new {
  my ($class, $text, $error, $thumb) = @_;
  
  my %randomcrop =
    (
     proportion => '25%'
    );

  unless ($text =~ s/^(\d+)x(\d+)(?:,|$)//) {
    $error = "randomcrop: no leading dimension";
    return;
  }
  my ($width, $height) = ( $1, $2 );

  $class->_build($text, 'randomcrop', \%randomcrop, $error)
    or return;
  
  @randomcrop{qw/width height/} = ( $width, $height );

  return bless \%randomcrop, $class;
}

sub size {
  my ($geo, $width, $height, $alpha) = @_;

  my $can_original = $width == $geo->{width} && $height == $geo->{height};
  if ($width > $geo->{width}) {
    $width = $geo->{width};
  }
  if ($height > $geo->{height}) {
    $height = $geo->{height};
  }

  return ( $width, $height, 0, $can_original );
}

sub do {
  my ($self, $work) = @_;

  my $in_width = $work->getwidth;
  my $in_height = $work->getheight;
  my $prop = $self->_percent($self->{proportion});
  $prop < 0.01 and $prop = 0.01;
  $prop > 0.90 and $prop = 0.90;
  my $scale_width = int($self->{width} / $prop);
  my $scale_height = int($self->{height} / $prop);

  my $scaled;
  if ($in_width > $scale_width &&
      $in_height > $scale_height) {
    $scaled = $work->scale(type => 'max',
			   xpixels => $scale_width,
			   ypixels => $scale_height,
			   qtype => 'mixing');
  }
  else {
    $scaled = $work;
  }
  my $xpos;
  my $out_width;
  if ($scaled->getwidth > $self->{width}) {
    $xpos = int(rand($scaled->getwidth() - $self->{width} + 1));
    $out_width = $self->{width};
  }
  else {
    $xpos = 0;
    $out_width = $in_width;
  }

  my $ypos;
  my $out_height;
  if ($scaled->getheight > $self->{height}) {
    $ypos = int(rand($scaled->getheight() - $self->{height} + 1));
    $out_height = $self->{height};
  }
  else {
    $ypos = 0;
    $out_height = $in_height;
  }

  return $scaled->crop(left => $xpos, width => $out_width,
		       top => $ypos, height => $out_height);
}

1;


