package BSE::Thumb::Imager;
use strict;
#use blib '/home/tony/dev/imager/maint/Imager/';

sub new {
  my ($class, $cfg) = @_;
  
  return bless { cfg => $cfg }, $class;
}

sub _parse_scale {
  my ($geometry, $error) = @_;

  my %geo = ( action => 'scale' );
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
      $$error = "scale:Both dimensions must be supplied for fill";
      return;
    }
  }

  return \%geo;
}

sub _parse_roundcorners {
  my ($text, $error) = @_;

  my %geo = 
    ( 
     action => 'roundcorners',
     tl => 10,
     tr => 10,
     bl => 10,
     br => 10,
     bg => 'FFFFFF',
     bgalpha => '255'
    );

  if ($text =~ s/^radi(?:us|i):([\d ]+),?//) {
    my @radii = split ' ', $1;
    if (@radii == 1) {
      $geo{tl} = $geo{tr} = $geo{br} = $geo{bl} = $radii[0];
    }
    elsif (@radii == 2) {
      $geo{tl} = $geo{tr} = $radii[0];
      $geo{bl} = $geo{br} = $radii[1];
    }
    elsif (@radii == 4) {
      @geo{qw/tl tr bl br/} = @radii;
    }
    else {
      $$error = 'roundcorners(radius:...) only accepts 1,2,4 radii';
      return;
    }
  }
  if ($text =~ s/^bg:([^,]+),?//) {
    $geo{bg} = $1;
  }
  if ($text =~ s/^bgalpha:(\d+)//) {
    $geo{bgalpha} = $1;
  }
  if (length $text) {
    $$error = "unexpected junk in roundcorners: $text";
    return;
  }

  \%geo;
}

sub _parse_geometry {
  my ($geometry, $error) = @_;

  my @geo;
  while (length $geometry) {
    if ($geometry =~ s/^scale\(([^\)]+)\)//) {
      my $scale = _parse_scale($1, $error)
	or return;
      push @geo, $scale;
    }
    elsif ($geometry =~ s/^roundcorners\(([^\)]*)\)//) {
      my $round = _parse_roundcorners($1, $error)
	or return;
      push @geo, $round;
    }
    else {
      $$error = "Unexpected junk at the end of the geometry $geometry";
      return;
    }
    $geometry =~ s/^,//;
  }

  return \@geo;
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
  my $geolist = _parse_geometry($geometry, \$error)
    or return;

  my $req_alpha = 0;

  for my $geo (@$geolist) {
    if ($geo->{action} eq 'scale') {
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
    }
    elsif ($geo->{action} eq 'roundcorners') {
      if ($geo->{bgalpha} != 255) {
	$req_alpha = 1;
      }
    }
  }
  
  return ($width, $height, $req_alpha);
}

sub _min {
  $_[0] < $_[1] ? $_[0] : $_[1];
}

sub _max {
  $_[0] > $_[1] ? $_[0] : $_[1];
}

sub _do_roundcorners {
  my ($src, $geo) = @_;

  use Data::Dumper;
  print STDERR "geo ", Dumper($geo);

  if ($src->getchannels == 1 || $src->getchannels == 2) {
    $src = $src->convert(preset => 'rgb');
  }

  my $bg = Imager::Color->new($geo->{bg});
  $bg->set(($bg->rgba)[0..2], $geo->{bgalpha});
  my $channels = $src->getchannels;
  if ($geo->{bgalpha} != 255 && $channels != 4) {
    $channels = 4;
    $src = $src->convert(preset => 'addalpha');
  }
  my $width = $src->getwidth;
  my $height = $src->getheight;
  my $out = Imager->new(xsize => $width, ysize => $height,
			channels => $channels);

  require Imager::Fill;
  my $fill = Imager::Fill->new(image => $src);
  
  # paste the rects, it should be faster
  # this will write some pixels multiple times if radii are different
  #$out->paste(left => $geo->{tl}, top => 0, src => $src,
#	      src_minx => $geo->{tl}, src_maxx => $width - $geo->{tr},
#	      height => _max($geo->{tl}, $geo->{tr}));
#  $out->paste(left => 0, top => $geo->{tl}, src => $src,
#	      src_miny => $geo->{tl}, src_maxy => $height - $geo->{bl},
#	      width => _max($geo->{tl}, $geo->{bl}));
#  my $right_width = _max($geo->{tr}, $geo->{br});
#  $out->paste(left => $width - $right_width, top => $geo->{tr}, src => $src,
#	      src_minx => $width - $right_width, 
  $out->paste(src => $src);
  if ($geo->{tl}) {
    $out->box(filled => 1, color => $bg, xmax => $geo->{tl}-1, ymax => $geo->{tl}-1);
    $out->arc(aa => 1, fill => $fill, r => $geo->{tl},
	      x => $geo->{tl}, y => $geo->{tl}, 
	      d1 => 175, d2 => 275);
  }
  if ($geo->{tr}) {
    $out->box(filled => 1, color => $bg, xmin => $width - $geo->{tr}, ymax => $geo->{tr}-1);
    $out->arc(aa => 1, fill => $fill, r => $geo->{tr},
	      x => $width - $geo->{tr}, y => $geo->{tr}, 
	      d1 => 265, d2 => 365);
  }
  if ($geo->{bl}) {
    $out->box(filled => 1, color => $bg, xmax => $geo->{bl}-1, 
	      ymin => $height - $geo->{bl});
    $out->arc(aa => 1, fill => $fill, r => $geo->{bl},
	      x => $geo->{bl}, y => $height - $geo->{bl}, 
	      d1 => 85, d2 => 185);
  }
  if ($geo->{br}) {
    $out->box(filled => 1, color => $bg, xmin => $width - $geo->{br}, 
	      ymin => $height - $geo->{br});
    $out->arc(aa => 1, fill => $fill, r => $geo->{br},
	      x => $width - $geo->{br}, y => $height - $geo->{br}, 
	      d1 => 355, d2 => 455);
  }

  return $out;
}

sub thumb_data {
  my ($self, $filename, $geometry, $error) = @_;

  my $geolist = _parse_geometry($geometry, $error)
    or return;

  require Imager;
  my $src = Imager->new;
  unless ($src->read(file => $filename)) {
    $$error = "Cannot read image $filename: ".$src->errstr;
    return;
  }

  my $work = $src;
  for my $geo (@$geolist) {
    if ($geo->{action} eq 'scale') {
      my $scaled = $work;
      if ($geo->{crop}) {
	my $width_scale = $geo->{width} / $work->getwidth;
	my $height_scale = $geo->{height} / $work->getheight;
	my $scale = $width_scale < $height_scale ? $height_scale : $width_scale;
	if ($scale < 1.0) {
	  $scaled = $work->scale(scalefactor => $scale, qtype=>'mixing');
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
	my $width = $work->getwidth;
	my $height = $work->getheight;
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
	$scaled = $work->scale(xpixels => $width, ypixels => $height, 
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
      $work = $result;
    }
    elsif ($geo->{action} eq 'roundcorners') {
      $work = _do_roundcorners($work, $geo);
    }
  }

  my $data;
  my $type = $src->tags(name => 'i_format');

  if ($work->getchannels == 4) {
    $type = 'png';
  }
  
  unless ($work->write(data => \$data, type => $type)) {
    $$error = "cannot write image ".$work->errstr;
    return;
  }

  return ( $data, "image/$type" );
}

1;
