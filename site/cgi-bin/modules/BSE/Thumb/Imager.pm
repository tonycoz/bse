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
  if ($geometry =~ s/^,fill:([^,]+)//) {
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

sub _parse_mirror {
  my ($text, $error) = @_;

  my %mirror =
    (
     action => 'mirror',
     height => '30%',
     bg => '000000',
     bgalpha => 255,
     opacity => '40%',
     srcx => 'x',
     srcy => 'y',
     horizon => '0',
     perspective => 0,
     perspectiveangle => '0',
    );

  while ($text =~ s/^(\w+):([^,]+),?//) {
    unless (exists $mirror{$1}) {
      $$error = "Unknown mirror parameter $1";
      return;
    }
      
    $mirror{$1} = $2;
  }
  
  if (length $text) {
    $$error = "unexpected junk in mirror: $text";
    return;
  }

  \%mirror;
}

sub _parse_sepia {
  my ($text, $error) = @_;

  my %sepia =
    (
     action => 'sepia',
     color => '000000',
    );
  if ($text =~ s/^([^,]+),?//) {
    $sepia{color} = $1;
  }
  if (length $text) {
    $$error = "unexpected junk in sepia: $text";
    return;
  }
  \%sepia;
}

sub _parse_filter {
  my ($text, $error) = @_;

  unless ($text =~ s/^(\w+),?//) {
    $$error = "filter: no filter name";
    return;
  }
  my %filter =
    (
     action => 'filter',
     type => $1
    );
  while ($text =~ s/^(\w+):([^,]+),?//) {
    $filter{$1} = $2;
  }

  \%filter;
}

sub _parse_conv {
  my ($text, $error) = @_;

  my @coef =  split /,/, $text;
  unless (@coef) {
    $$error = "No coefficients";
    return;
  }
  return
    {
     action => 'filter',
     type => 'conv',
     coef => \@coef,
    };
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
    elsif ($geometry =~ s/^mirror\(([^\)]*)\)//) {
      my $mirror = _parse_mirror($1, $error)
	or return;
      push @geo, $mirror;
    }
    elsif ($geometry =~ s/^grey\(\)//) {
      push @geo, { action => 'grey' };
    }
    elsif ($geometry =~ s/^sepia\(([^\)]*)\)//) {
      my $sepia = _parse_sepia($1, $error)
	or return;
      push @geo, $sepia;
    }
    elsif ($geometry =~ s/^filter\(([^\)]*)\)//) {
      my $filter = _parse_filter($1, $error)
	or return;
      push @geo, $filter;
    }
    elsif ($geometry =~ s/^conv\(([^\)]*)\)//) {
      my $conv = _parse_conv($1, $error)
	or return;
      push @geo, $conv;
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
  my $use_original = 1;

  for my $geo (@$geolist) {
    my $can_original = 0;
    if ($geo->{action} eq 'scale') {
      if ($geo->{fill}) {
	# fill always produces an image the right size
	$can_original = $geo->{width} == $width && $geo->{height} == $height;
	($width, $height) = @$geo{qw/width height/};
      }
      else {
	if ($geo->{crop}) {
	  my ($start_width, $start_height) = ($width, $height);
	  my $width_scale = $geo->{width} / $width;
	  my $height_scale = $geo->{height} / $height;
	  my $scale = $width_scale < $height_scale ? $height_scale : $width_scale;
	  
	  $width *= $scale;
	  $height *= $scale;
	  $width > $geo->{width} and $width = $geo->{width};
	  $height > $geo->{height} and $height = $geo->{height};
	  $can_original = $start_width == $width && $start_height == $height && $scale == 1;
	}
	else {
	  my ($start_width, $start_height) = ($width, $height);
	  if ($geo->{width} && $width > $geo->{width}) {
	    $height = $height * $geo->{width} / $width;
	    $width = $geo->{width};
	  }
	  if ($geo->{height} && $height > $geo->{height}) {
	    $width = $width * $geo->{height} / $height;
	    $height = $geo->{height};
	  }
	  $can_original = $start_width == $width && $start_height == $height;
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
    elsif ($geo->{action} eq 'mirror') {
      $height += _percent_of($geo->{height}, $height)
	+ _percent_of($geo->{horizon}, $height);
      $height = int($height);
      if ($geo->{perspective}) {
	my $p = abs($geo->{perspective});
	$width = int($width / (1 + $p * $width) + 1);
      }
	
      if ($geo->{bgalpha} != 255) {
	$req_alpha = 1;
      }
    }

    $use_original &&= $can_original;
  }

  return ($width, $height, $req_alpha, $use_original);
}

sub _min {
  $_[0] < $_[1] ? $_[0] : $_[1];
}

sub _max {
  $_[0] > $_[1] ? $_[0] : $_[1];
}

sub _do_roundcorners {
  my ($src, $geo) = @_;

  if ($src->getchannels == 1 || $src->getchannels == 2) {
    $src = $src->convert(preset => 'rgb');
  }

  my $bg = _bgcolor($geo);
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
  
  $out = $src->copy;
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

sub _do_mirror {
  my ($work, $mirror) = @_;

  if ($work->getchannels < 3) {
    $work = $work->convert(preset => 'rgb');
  }
  if ($mirror->{bgalpha} != 255) {
    $work = $work->convert(preset => 'addalpha');
  }

  my $bg = _bgcolor($mirror);

  my $oldheight = $work->getheight();
  my $height = $oldheight;
  my $gap = int(_percent_of($mirror->{horizon}, $oldheight));
  my $add_height = int(_percent_of($mirror->{height}, $oldheight));
  $height += $gap + $add_height;

  my $out = Imager->new(xsize => $work->getwidth, ysize => $height,
			channels => $work->getchannels);
  $out->box(filled => 1, color => $bg);

  if ($work->getchannels == 4) {
    $out->rubthrough(src => $work)
      or print STDERR $out->errstr, "\n";
  }
  else {
    $out->paste(src => $work)
      or print STDERR $out->errstr, "\n";
  }

  $work->flip(dir => 'v');

  $work = $work->crop(bottom => $add_height);
  
  $work = Imager::transform2
    (
     {
      channels => 4,
      constants =>
      {
       opacity => _percent($mirror->{opacity})
      },
      rpnexpr => <<EOS,
$mirror->{srcx} !srcx
$mirror->{srcy} !srcy
\@srcx \@srcy getp1 !p
\@p red \@p green \@p blue 
\@p alpha opacity h y - h / * * rgba
EOS
     },
     $work
    ) or die Imager->errstr;
  $out->rubthrough(src => $work, ty => $oldheight + $gap);

  if ($mirror->{perspective}) {
    require Imager::Matrix2d;
    my $old_width = $out->getwidth;
    my $p = abs($mirror->{perspective});
    my $new_width = $old_width / (1 + $p * $old_width) + 1;
    my $angle = sin($mirror->{perspectiveangle} * 3.1415926 / 180);
    my $persp = bless [ 1, 0, 0, 
			-$angle, 1, 0,
			-abs($p), 0, 1 ], 'Imager::Matrix2d';
    $out->flip(dir => 'v');
    $mirror->{perspective} < 0 and $out->flip(dir => 'h');
    my $temp = $out->matrix_transform(matrix=> $persp, back=>$bg, xsize => $new_width)
      or print STDERR "failed", $work->errstr, "\n";
    $out = $temp;
    $mirror->{perspective} < 0 and $out->flip(dir => 'h');
    $out->flip(dir => 'v');
  }


  $out;
}

sub _do_sepia {
  my ($work, $sepia) = @_;

  require Imager::Filter::Sepia;
  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;
  my $color = Imager::Color->new($sepia->{color});
  $work->filter(type => 'sepia', tone => $color);

  $work;
}

sub _do_filter {
  my ($work, $filter) = @_;

  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;

  $work->filter(%$filter)
    or die $work->errstr;

  $work;
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
    elsif ($geo->{action} eq 'mirror') {
      $work = _do_mirror($work, $geo);
    }
    elsif ($geo->{action} eq 'grey') {
      $work = $work->convert(preset => 'grey');
      print STDERR "channels ", $work->getchannels, "\n";
    }
    elsif ($geo->{action} eq 'sepia') {
      $work = _do_sepia($work, $geo);
    }
    elsif ($geo->{action} eq 'filter') {
      $work = _do_filter($work, $geo);
    }
  }

  my $data;
  my $type = $src->tags(name => 'i_format');

  if ($work->getchannels == 4 || $work->getchannels == 2) {
    $type = 'png';
  }
  
  unless ($work->write(data => \$data, type => $type)) {
    $$error = "cannot write image ".$work->errstr;
    return;
  }

  return ( $data, "image/$type" );
}

sub _percent {
  my ($num) = @_;

  if ($num =~ s/%$//) {
    $num /= 100.0;
  }
  $num;
}

sub _percent_of {
  my ($num, $base) = @_;

  if ($num =~ s/%$//) {
    return $base * $num / 100.0;
  }
  else {
    return $num;
  }
}

sub _bgcolor {
  my ($spec) = @_;

  my $bg = Imager::Color->new($spec->{bg});
  $bg->set(($bg->rgba)[0..2], $spec->{bgalpha});

  $bg;
}

1;
