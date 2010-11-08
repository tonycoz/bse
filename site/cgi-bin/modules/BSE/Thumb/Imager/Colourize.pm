package BSE::Thumb::Imager::Colourize;
use strict;
use base 'BSE::Thumb::Imager::Handler';

our $VERSION = "1.000";

sub new {
  my ($class, $text, $error, $thumb) = @_;
  
  my %colourize =
    (
     black => '000000',
     white => 'FFFFFF',
    );

  $class->_build($text, 'colourize', \%colourize, $error)
    or return;
  
  return bless \%colourize, $class;
}

sub size {
  my ($geo, $width, $height, $alpha) = @_;

  return ( $width, $height, $alpha, 0 );
}

sub do {
  my ($self, $work) = @_;

  my $in_width = $work->getwidth;
  my $in_height = $work->getheight;

  if ($work->getchannels > 2) {
    $work = $work->convert(preset => "grey");
  }
  
  my @black = Imager::Color->new($self->{black})->rgba;
  my @white = Imager::Color->new($self->{white})->rgba;

  my @alpha;
  push @alpha, 0 if $work->getchannels == 2;

  my @matrix =
    (
     [ ($white[0] - $black[0]) / 255.0, @alpha, $black[0]/255.0 ],
     [ ($white[1] - $black[1]) / 255.0, @alpha, $black[1]/255.0 ],
     [ ($white[2] - $black[2]) / 255.0, @alpha, $black[2]/255.0 ],
    );

  if (@alpha) {
    push @matrix, [ 0, 1, 0 ];
  }

  return $work->convert(matrix => \@matrix);
}

1;


