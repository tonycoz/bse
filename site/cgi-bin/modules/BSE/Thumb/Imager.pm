package BSE::Thumb::Imager;
use strict;
#use blib '/home/tony/dev/imager/maint/Imager/';
use Imager;

sub new {
  my ($class, $cfg) = @_;
  
  return bless { cfg => $cfg }, $class;
}

sub _parse_geometry {
  my ($geometry, $error) = @_;

  my %geo;
  if ($geometry =~ s/^(\d+)x(\d+)//) {
    @geo{qw(width height)} = ( $1, $2 );
  }
  elsif ($geometry =~ s/^x(\d+)//) {
    $geo{height} = $1;
  }
  elsif ($geometry =~ s/^(\d+)x//) {
    $geo{width} = $1;
  }
  elsif ($geometry =~ s/^(\d+)//) {
    $geo{width} = $geo{height} = $1;
  }
  else {
    $$error = "No leading dimension";
    return;
  }

  if ($geometry =~ s/^,?c//) {
    $geo{crop} = 1;
    if (!$geo{width} || !$geo{height}) {
      $$error = "Both dimensions much be supplied for crop";
      return;
    }
  }
  if ($geometry =~ s/^,fill\(([^,]+)\)//) {
    $geo{fill} = $1;
    if (!$geo{width} || !$geo{height}) {
      $$error = "Both dimensions must be supplied for fill";
      return;
    }
  }

  return \%geo;
}

sub validate_geometry {
  my ($self, $geometry, $rerror) = @_;

  _parse_geometry($geometry, $rerror)
    or return;

  return 1;
}

sub thumb_dimensions_sized {
  my ($self, $geometry, $width, $height) = @_;

  my $error;
  my $geo = _parse_geometry($geometry, \$error)
    or return;

  if ($geo->{fill}) {
    # fill always produces an image the right size
    return @$geo{qw/width height/};
  }

  if ($geo->{crop}) {
    my $width_scale = $geo->{width} / $width;
    my $height_scale = $geo->{height} / $height;
    my $scale = $width_scale < $height_scale ? $height_scale : $width_scale;

    $width *= $scale;
    $height *= $scale;
    $width > $geo->{width} and $width = $geo->{width};
    $height > $geo->{height} and $height = $geo->{height};
  }
  else {
    if ($geo->{width} && $width > $geo->{width}) {
      $height = $height * $geo->{width} / $width;
      $width = $geo->{width};
    }
    if ($geo->{height} && $height > $geo->{height}) {
      $width = $width * $geo->{height} / $height;
      $height = $geo->{height};
    }
    $width = int($width);
    $height = int($height);
  }
  
  return ($width, $height);
}

sub thumb_data {
  my ($self, $filename, $geometry, $error) = @_;

  my $geo = _parse_geometry($geometry, $error)
    or return;

  my $src = Imager->new;
  unless ($src->read(file => $filename)) {
    $$error = "Cannot read image $filename: ".$src->errstr;
    return;
  }

  my $scaled = $src;
  if ($geo->{crop}) {
    my $width_scale = $geo->{width} / $src->getwidth;
    my $height_scale = $geo->{height} / $src->getheight;
    my $scale = $width_scale < $height_scale ? $height_scale : $width_scale;
    if ($scale < 1.0) {
      $scaled = $src->scale(scalefactor => $scale, qtype=>'mixing');
    }
    my $width = $scaled->getwidth;
    if ($width > $geo->{width}) {
      $scaled = $scaled->crop(left => ($width-$geo->{width})/2, width => $geo->{width});
    }
    my $height = $scaled->getheight;
    if ($height > $geo->{height}) {
      $scaled = $scaled->crop(top => ($height - $geo->{height}) / 2,
			      height => $geo->{height});
    }
  }
  else {
    my $width = $src->getwidth;
    my $height = $src->getheight;
    if ($geo->{width} && $width > $geo->{width}) {
      $height = $height * $geo->{width} / $width;
      $width = $geo->{width};
    }
    if ($geo->{height} && $height > $geo->{height}) {
      $width = $width * $geo->{height} / $height;
      $height = $geo->{height};
    }
    $width = int($width);
    $height = int($height);
    $scaled = $src->scale(xpixels => $width, ypixels => $height, 
			  qtype => 'mixing');
  }

  my $result = $scaled;
  if ($geo->{fill} && 
      ($scaled->getwidth < $geo->{width} || $scaled->getheight < $geo->{height})) {
    $result = Imager->new(xsize => $geo->{width}, ysize => $geo->{height});
    $result->box(color => $geo->{fill}, filled => 1);
    $result->paste(left => ($geo->{width} - $scaled->getwidth) / 2,
		   top => ($geo->{height} - $scaled->getheight) / 2 ,
		   img => $scaled);
  }

  my $data;
  my $type = $src->tags(name => 'i_format');

  unless ($result->write(data => \$data, type => $type)) {
    $$error = "cannot write image ".$result->errstr;
    return;
  }

  return ( $data, "image/$type" );
}

1;
