package BSE::Thumb::Imager;
use strict;
use constant CFG_SECTION => 'imager thumb driver';
use Config;

my %handlers =
  (
   # default handlers
   scale => 'BSE::Thumb::Imager::Scale',
   roundcorners => 'BSE::Thumb::Imager::RoundCorners',
   mirror => 'BSE::Thumb::Imager::Mirror',
   sepia => 'BSE::Thumb::Imager::Sepia',
   grey => 'BSE::Thumb::Imager::Grey',
   filter => 'BSE::Thumb::Imager::Filter',
   conv => 'BSE::Thumb::Imager::Conv',
   border => 'BSE::Thumb::Imager::Border',
   rotate => 'BSE::Thumb::Imager::Rotate',
   perspective => 'BSE::Thumb::Imager::Perspective',
   canvas => 'BSE::Thumb::Imager::Canvas',
   format => 'BSE::Thumb::Imager::Format',
  );

sub new {
  my ($class, $cfg) = @_;
  
  return bless { cfg => $cfg }, $class;
}

sub _handler {
  my ($self, $op) = @_;

  $handlers{$op};
}

sub _parse_geometry {
  my ($self, $geometry, $error) = @_;

  my @geo;
  while (length $geometry) {
    if ($geometry =~ s/^(\w+)\(([^\)]+)\)//) {
      my ($op, $args) = ( $1, $2 );
      my $handler_class = $self->_handler($op);
      unless ($handler_class) {
	$$error = "Unknown operator $op";
	return;
      }
      my $geo = $handler_class->new($args, $error, $self)
	or return;

      push @geo, $geo;
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

  $self->_parse_geometry($geometry, $rerror)
    or return;

  return 1;
}

sub thumb_dimensions_sized {
  my ($self, $geometry, $width, $height, $type) = @_;

  my $error;
  my $geolist = $self->_parse_geometry($geometry, \$error)
    or return;

  my $use_original = 1;

  for my $geo (@$geolist) {
    my ($can_original, $new_type);

    ($width, $height, $new_type, $can_original)
      = $geo->size($width, $height);

    $new_type and $type = $new_type;
    $use_original &&= $can_original;
  }

  return ($width, $height, $type, $use_original);
}

sub thumb_data {
  my ($self, $filename, $geometry, $error) = @_;

  my $geolist = $self->_parse_geometry($geometry, $error)
    or return;

  my $blib = $self->{cfg}->entry(CFG_SECTION, 'blib');
  if ($blib) {
    require blib;
    blib->import(split /,/, $blib);
  }
  require Imager;
  my $src = Imager->new;
  unless ($src->read(file => $filename)) {
    $$error = "Cannot read image $filename: ".$src->errstr;
    return;
  }

  my $jpeg_quality = $self->{cfg}->entry(CFG_SECTION, 'jpegquality', 90);
  my %write_opts =
    ( 
     jpegquality => $jpeg_quality,
     make_colors => 'mediancut',
     translate => 'errdiff',
     gifquant => 'gen',
    );

  my $work = $src;
  for my $geo (@$geolist) {
    $work = $geo->do($work, \%write_opts);
  }

  if ($work->getchannels == 4 || $work->getchannels == 2) {
    $write_opts{type} ||= 'png';
  }
  $write_opts{type} ||= $src->tags(name => 'i_format');

  my $type = $write_opts{type};

  if ($type eq 'jpeg' &&
      ($work->getchannels == 2 || $work->getchannels == 4)) {
    my $tmp = Imager->new(xsize => $work->getwidth, ysize => $work->getheight,
			  channels => $work->getchannels() - 1);
    $tmp->box(filled => 1, color => $write_opts{bgcolor});
    $tmp->rubthrough(src => $work);
    $work = $tmp;
  }

  use Data::Dumper;
  print STDERR Dumper \%write_opts;
  my $data;
  $work = $work->to_rgb8;
  unless ($work->write(data => \$data, %write_opts)) {
    $$error = "cannot write image ".$work->errstr;
    return;
  }

  return ( $data, "image/$type" );
}

sub _incs {
  my $self = shift;

  split $Config{path_sep}, $self->{cfg}->entry(CFG_SECTION, 'include', '');
}

sub find_file {
  my ($self, $filename) = @_;

  if ($filename =~ q!^/! && -e $filename) {
    return $filename;
  }

  my @incs = $self->_incs;

  for my $dir (@incs) {
    -e "$dir/$filename"
      and return "$dir/$filename";
  }

  return;
}

sub find_file_or_die {
  my ($self, $filename) = @_;

  my $result = $self->find_file($filename)
    or die "Cannot find $filename";

  return $result;
}

package BSE::Thumb::Imager::Handler;

sub new {
  my ($class, $geometry, $error) = @_;

  $$error = "$class needs to define a new method";

  return;
}

# parse key:foo,key2:foo2 string
sub _build {
  my ($class, $text, $op, $base, $error) = @_;

  while ($text =~ s/^(\w+):([^,]+),?//) {
    unless (exists $base->{$1}) {
      $$error = "Unknown $op parameter $1";
      return;
    }
      
    $base->{$1} = $2;
  }

  if (length $text) {
    $$error = "unexpected junk in op: $text";
    return;
  }
  
  $base;
}

sub size {
  my ($self, $width, $height) = @_;

  return ( $width, $height );
}

sub _bgcolor {
  my ($spec) = @_;

  my $bg = Imager::Color->new($spec->{bg});
  $bg->set(($bg->rgba)[0..2], $spec->{bgalpha});

  $bg;
}

sub _percent {
  my ($self, $num) = @_;

  if ($num =~ s/%$//) {
    $num /= 100.0;
  }
  $num;
}

sub _percent_of {
  my ($self, $num, $base) = @_;

  if ($num =~ s/%$//) {
    return $base * $num / 100.0;
  }
  else {
    return $num;
  }
}

sub _percent_of_rounded {
  my ($self, $num, $base) = @_;

  return sprintf("%.0f", $self->_percent_of($num, $base));
}


package BSE::Thumb::Imager::Scale;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $geometry, $error) = @_;

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
  if ($geometry =~ s/^,fill:([^,]+)//) {
    $geo{fill} = $1;
    if (!$geo{width} || !$geo{height}) {
      $$error = "scale:Both dimensions must be supplied for fill";
      return;
    }
  }

  return bless \%geo, $class;
}

sub size {
  my ($geo, $width, $height, $alpha) = @_;

  my $can_original;
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
      $scale >= 1 and $scale = 1;
      
      $width *= $scale;
      $height *= $scale;
      $width = int($width);
      $height = int($height);
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
      $width = int($width+0.5);
      $height = int($height+0.5);
      $can_original = $start_width == $width && $start_height == $height;
    }
  }

  return ($width, $height, 0, $can_original);
}

sub do {
  my ($geo, $work) = @_;

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

  return $result;
}

package BSE::Thumb::Imager::RoundCorners;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  my %geo = 
    ( 
     tl => 10,
     tr => 10,
     br => 10,
     bl => 10,
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
      $geo{br} = $geo{bl} = $radii[1];
    }
    elsif (@radii == 4) {
      @geo{qw/tl tr br bl/} = @radii;
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
      
      bless \%geo, $class;
}

sub size {
  my ($self, $width, $height) = @_;

  return ( $width, $height, $self->{bgalpha} != 255 && 'png' );
}

sub do {
  my ($geo, $src) = @_;

  if ($src->getchannels == 1 || $src->getchannels == 2) {
    $src = $src->convert(preset => 'rgb');
  }

  my $bg = $geo->_bgcolor;
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

package BSE::Thumb::Imager::Mirror;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  my %mirror =
    (
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

  $class->_build($text, 'mirror', \%mirror, $error)
    or return;

  bless \%mirror, $class;
}

sub size {
  my ($geo, $width, $height) = @_;

  $height += $geo->_percent_of($geo->{height}, $height)
    + $geo->_percent_of($geo->{horizon}, $height);
  $height = int($height);
  if ($geo->{perspective}) {
    my $p = abs($geo->{perspective});
    $width = int($width / (1 + $p * $width) + 1);
  }

  return ( $width, $height, $geo->{bgalpha} != 255 && 'png' );
}

sub do {
  my ($mirror, $work) = @_;

  if ($work->getchannels < 3) {
    $work = $work->convert(preset => 'rgb');
  }
  if ($mirror->{bgalpha} != 255) {
    $work = $work->convert(preset => 'addalpha');
  }

  my $bg = $mirror->_bgcolor;

  my $oldheight = $work->getheight();
  my $height = $oldheight;
  my $gap = int($mirror->_percent_of($mirror->{horizon}, $oldheight));
  my $add_height = int($mirror->_percent_of($mirror->{height}, $oldheight));
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
       opacity => $mirror->_percent($mirror->{opacity})
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

package BSE::Thumb::Imager::Sepia;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  my %sepia =
    (
     color => '000000',
    );

  $class->_build($text, 'sepia', \%sepia, $error)
    or return;

  bless \%sepia, $class;
}

# use base's size()

sub do {
  my ($sepia, $work) = @_;

  require Imager::Filter::Sepia;
  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;
  my $color = Imager::Color->new($sepia->{color});
  $work->filter(type => 'sepia', tone => $color);

  $work;
}

package BSE::Thumb::Imager::Grey;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  unless ($text eq '') {
    $$error = "grey takes no parameters";
    return;
  }

  bless {}, $class;
}

# use base's size()

sub do {
  my ($self, $work) = @_;

  $work->convert(preset => 'grey');
}

package BSE::Thumb::Imager::Filter;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  unless ($text =~ s/^(\w+),?//) {
    $$error = "filter: no filter name";
    return;
  }
  my %filter =
    (
     type => $1
    );

  while ($text =~ s/^(\w+):([^,]+),?//) {
    $filter{$1} = $2;
  }

  if (length $text) {
    $$error = "unexpected junk in filter: $text";
    return;
  }

  bless \%filter, $class;
}

# fall through to base size()

sub do {
  my ($filter, $work) = @_;

  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;

  $work->filter(%$filter)
    or die $work->errstr;

  $work;
}

package BSE::Thumb::Imager::Conv;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Filter';

sub new {
  my ($class, $text, $error) = @_;

  my @coef =  split /,/, $text;
  unless (@coef) {
    $$error = "No coefficients";
    return;
  }
  return
    bless 
      {
       type => 'conv',
       coef => \@coef,
      }, $class;
}

# fall through to base size(), do()

package BSE::Thumb::Imager::Border;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  my %border =
    (
     bg => '000000',
     bgalpha => 255,
     width => '2',
    );

  $class->_build($text, 'border', \%border, $error)
    or return;

  # parse out the border
  my @widths = split ' ', $border{width};
  if (@widths == 1) {
    $border{top} = $border{bottom} = $border{left} = 
      $border{right} = $widths[0];
  }
  elsif (@widths == 2) {
    $border{top} = $border{bottom} = $widths[0];
    $border{left} = $border{right} = $widths[1];
  }
  elsif (@widths == 4) {
    @border{qw/top right bottom left/} = @widths;
  }
  else {
    $$error = 'border(width:...) only accepts 1,2,4 widths';
    return;
  }

  bless \%border, $class;
}

sub size {
  my ($geo, $width, $height) = @_;

  $height += $geo->_percent_of_rounded($geo->{top}, $height) 
    + $geo->_percent_of($geo->{bottom}, $height);
  $width += $geo->_percent_of($geo->{left}, $width) 
    + $geo->_percent_of_rounded($geo->{right}, $width);

  return ( $width, $height, $geo->{bgalpha} != 255 && 'png' );
}

sub do {
  my ($border, $work) = @_;

  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;
  my $channels = $work->getchannels;
  $border->{bgalpha} != 255 and $channels = 4;
  my $top = $border->_percent_of_rounded($border->{top}, $work->getheight);
  my $right = $border->_percent_of_rounded($border->{right}, $work->getwidth);
  my $bottom = $border->_percent_of_rounded($border->{bottom}, $work->getheight);
  my $left = $border->_percent_of_rounded($border->{left}, $work->getwidth);

  my $bg = $border->_bgcolor;
  my $out = Imager->new(xsize => $left + $right + $work->getwidth,
			ysize => $top + $bottom + $work->getheight,
			channels => $channels);
  
  # draw the borders
  my %box = ( filled => 1, color => $bg );
  $top 
    and $out->box(%box, ymax => $top-1);
  $bottom
    and $out->box(%box, ymin => $out->getheight() - $bottom);
  $left
    and $out->box(%box, xmax => $left-1);
  $right
    and $out->box(%box, xmin => $out->getwidth() - $right);

  $out->paste(src => $work, left => $left, top => $top);

  return $out;
}

package BSE::Thumb::Imager::Rotate;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

use List::Util qw(max);
use constant PI => 3.14159265358979;
use POSIX qw(ceil);

sub new {
  my ($class, $text, $error) = @_;

  my %rotate =
    (
     bg => '000000',
     bgalpha => 0,
     angle => 90,
    );

  $class->_build($text, 'rotate', \%rotate, $error)
    or return;

  if ($rotate{angle} >= 360) {
    $rotate{angle} %= 360;
  }

  bless \%rotate, $class;
}

sub size {
  my ($geo, $width, $height) = @_;

  my $angle = $geo->{angle} * PI / 180;
  my $cos = cos($angle);
  my $sin = sin($angle);
  my $new_width = ceil(max(abs($width * $cos + $height * $sin),
			   abs($width * $cos - $height * $sin)));
  my $new_height = ceil(max(abs($width * -$sin + $height * $cos),
			    abs($width * -$sin - $height * $cos)));
  $width = $new_width;
  $height = $new_height;
  
  return ($width, $height, $geo->{bgalpha} != 255 && 'png');
}

sub do {
  my ($rotate, $work) = @_;

  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;

  $work = $work->convert(preset => 'addalpha')
    if $rotate->{bgalpha} != 255;

  my $bg = $rotate->_bgcolor;

  my $out = $work->rotate(degrees => $rotate->{angle}, back => $bg)
    or print STDERR "rotation error: ", $work->errstr, "\n";

  $out;
}

package BSE::Thumb::Imager::Perspective;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error) = @_;

  my %perspective =
    (
     bg => '000000',
     bgalpha => 255,
     perspective => 0,
     perspectiveangle => '0',
    );

  unless ($text =~ s/^(-?[\d.]+),//) {
    $$error = "perspective: no perspective amount";
    return;
  }
  $perspective{perspective} = $1;
  $class->_build($text, 'perspective', \%perspective, $error)
    or return;

  bless \%perspective, $class;
}

sub size {
  my ($geo, $width, $height) = @_;

  if ($geo->{perspective}) {
    my $p = abs($geo->{perspective});
    $width = int($width / (1 + $p * $width) + 1);
  }

  return ( $width, $height, $geo->{bgalpha} != 255 && 'png' );
}

sub do {
  my ($mirror, $work) = @_;

  if ($work->getchannels < 3) {
    $work = $work->convert(preset => 'rgb');
  }
  if ($mirror->{bgalpha} != 255) {
    $work = $work->convert(preset => 'addalpha');
  }

  my $bg = $mirror->_bgcolor;

  require Imager::Matrix2d;
  my $old_width = $work->getwidth;
  my $p = abs($mirror->{perspective});
  my $new_width = $old_width / (1 + $p * $old_width) + 1;
  my $angle = sin($mirror->{perspectiveangle} * 3.1415926 / 180);
  my $persp = bless [ 1, 0, 0, 
		      -$angle, 1, 0,
		      -abs($p), 0, 1 ], 'Imager::Matrix2d';
  $work->flip(dir => 'v');
  $mirror->{perspective} < 0 and $work->flip(dir => 'h');
  my $temp = $work->matrix_transform(matrix=> $persp, back=>$bg, xsize => $new_width)
    or print STDERR "failed", $work->errstr, "\n";
  $work = $temp;
  $mirror->{perspective} < 0 and $work->flip(dir => 'h');
  $work->flip(dir => 'v');

  $work;
}

package BSE::Thumb::Imager::Canvas;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error, $thumb) = @_;

  my %canvas =
    (
     bg => '000000',
     bgalpha => 255,
     bgfile => '',
     bgtile => 0,
     bgrepeat => 'both',
     bgxpos => 0,
     bgypos => 0,
     bgrotate => 0,
     bggrad => '',
     gradtype => 'linear',
     gradrepeat => 'none',
     gradx1 => '0%',
     grady1 => '0%',
     gradx2 => '100%',
     grady2 => '100%',
     xpos => '50%',
     ypos => '50%',
    );

  my ($width, $height);
  my $dim_re = qr/\d+%|\+?\d+/;
  if ($text =~ s/^($dim_re)x($dim_re)//) {
    ($width, $height) = ( $1, $2 );
  }
  elsif ($text =~ s/^x($dim_re)//) {
    $height = $1;
  }
  elsif ($text =~ s/^($dim_re)x//) {
    $width = $1;
  }
  elsif ($text =~ s/^($dim_re)//) {
    $width = $height = $1;
  }
  else {
    $$error = "canvas: No leading dimension";
    return;
  }
  if (length $text && $text !~ s/^,//) {
    $$error = "canvas: missing comma $text";
    return;
  }
  
  $class->_build($text, 'canvas', \%canvas, $error)
    or return;

  @canvas{qw/width height/} = ($width, $height);

  if ($canvas{bgfile}) {
    $canvas{bgfile} = $thumb->find_file_or_die($canvas{bgfile});
  }

  if ($canvas{bggrad}) {
    $canvas{bggrad} = $thumb->find_file_or_die($canvas{bggrad});
  }
  grep $_ eq $canvas{bgrepeat}, qw/none x y both/
    or die "canvas: Invalid bgrepeat $canvas{bgrepeat}";

  bless \%canvas, $class;
}

sub _calc_dim {
  my ($self, $base, $spec) = @_;

  if ($spec =~ /\%$/) {
    return $self->_percent_of_rounded($spec, $base);
  }
  elsif ($spec =~ /^\+\d+$/) {
    return $base + $spec;
  }
  else {
    return $spec;
  }
}

sub _calc_pos {
  my ($self, $spec, $base, $max) = @_;

  if ($spec =~ /%$/) {
    #$base >= $max and return 0;
    return $self->_percent_of_rounded($spec, $max-$base);
  }
  else {
    return $spec;
  }
}

sub size {
  my ($self, $width, $height) = @_;

  my $want_width = defined $self->{width} ?
    $self->_calc_dim($width, $self->{width}) : $width;
  my $want_height = defined $self->{height} ? 
    $self->_calc_dim($height, $self->{height}) : $height;
  my $want_xpos = $self->_calc_pos($self->{xpos}, $width, $want_width);
  my $want_ypos = $self->_calc_pos($self->{ypos}, $height, $want_height);

  $width < $want_width and $width = $want_width;
  $height < $want_height and $height = $want_height;

  return ( $width, $height, $self->{bgalpha} != 255 && 'png' );
}

sub do {
  my ($self, $work) = @_;

  if ($work->getchannels < 3) {
    $work = $work->convert(preset => 'rgb');
  }
  if ($self->{bgalpha} != 255 && $work->getchannels != 4) {
    $work = $work->convert(preset => 'addalpha');
  }

  my $bg = $self->_bgcolor;

  my $width = $work->getwidth;
  my $height = $work->getheight;
  my $want_width = defined $self->{width} ? 
    $self->_calc_dim($width, $self->{width}) : $width;
  my $want_height = defined $self->{height} ? 
    $self->_calc_dim($height, $self->{height}) : $height;
  $width > $want_width and $want_width = $width;
  $height > $want_height and $want_height = $height;
  my $want_xpos = $self->_calc_pos($self->{xpos}, $width, $want_width);
  my $want_ypos = $self->_calc_pos($self->{ypos}, $height, $want_height);

  ($width, $height) = ($want_width, $want_height);
  
  my $out_channels = $self->{bgalpha} != 255 ? 4 : 3;
  my $out = Imager->new(xsize => $width, ysize => $height, 
			channels => $out_channels);
  $out->box(filled => 1, color => $bg);

  if ($self->{bgfile}) {
    my $bg = Imager->new;
    $bg->read(file => $self->{bgfile})
      or die "Cannot load $self->{bgfile}: ", $bg->errstr;
    $bg->getchannels >= 3 or $bg = $bg->convert(preset => 'rgb');
    if ($self->{bgtile}) {
      my $xpos = $self->_calc_pos($self->{bgxpos}, $bg->getwidth, $want_width);
      my $ypos = $self->_calc_pos($self->{bgypos}, $bg->getheight, $want_height);
      my %opts = ( xmin => $xpos, ymin => $ypos );
      if ($self->{bgrepeat} eq 'x' || $self->{bgrepeat} eq 'none') {
	$opts{ymax} = $ypos + $bg->getheight() - 1;
      }
      if ($self->{bgrepeat} eq 'y' || $self->{bgrepeat} eq 'none') {
	$opts{xmax} = $xpos + $bg->getwidth() - 1;
      }
      my $matrix;
      if ($xpos || $ypos) {
	require Imager::Matrix2d;
	$matrix = Imager::Matrix2d->translate(x => -$xpos, y => -$ypos);
      }
      if ($self->{bgrotate}) {
	require Imager::Matrix2d;
	$matrix ||= Imager::Matrix2d->identity;
	$matrix *= Imager::Matrix2d->rotate(degrees => $self->{bgrotate});
      }
      $bg->getchannels == $out->getchannels
	or $bg = $bg->convert(preset => 'addalpha');
      $out->box(fill => { image => $bg, matrix => $matrix, combine => 'normal' }, %opts);
    }
    else {
      if ($bg->getwidth != $want_width || $bg->getheight != $want_height) {
	$bg = $bg->scale(xpixels => $want_width, ypixels => $want_height,
			 qtype => 'mixing', type => 'nonprop');
      }
      if ($bg->getchannels < 3) {
	$bg = $bg->convert(preset => 'rgb');
      }
      if ($bg->getchannels != $out->getchannels) {
	$bg = $bg->convert(preset => 'addalpha');
      }
      if ($bg->getchannels == 3) {
	$out->paste(src => $bg);
      }
      else {
	$out->rubthrough(src => $bg);
      }
    }
  }
  if ($self->{bggrad}) {
    require Imager::Fountain;
    my $grad = Imager::Fountain->read(gimp => $self->{bggrad})
      or die "Cannot load $self->{bggrad}: ", Imager->errstr;

    my $x1 = $self->_calc_dim($want_width, $self->{gradx1});
    my $y1 = $self->_calc_dim($want_height, $self->{grady1});
    my $x2 = $self->_calc_dim($want_width, $self->{gradx2});
    my $y2 = $self->_calc_dim($want_height, $self->{grady2});

    print STDERR "x1 $x1 y1 $y1 x2 $x2 y2 $x2\n";
    $out->box(fill => { fountain => $self->{gradtype},
			combine => 'normal',
			segments => $grad,
			repeat => $self->{gradrepeat},
			xa => $x1, ya => $y1, xb => $x2, yb => $y2 })
      or die "Cannot do gradient: ", $out->errstr;
  }

  if ($work->getchannels == 3) {
    $out->paste(src => $work, left => $want_xpos, top => $want_ypos);
  }
  else {
    $out->rubthrough(src => $work, tx => $want_xpos, ty => $want_ypos);
  }

  $out;
}

package BSE::Thumb::Imager::Format;
use vars qw(@ISA);
@ISA = 'BSE::Thumb::Imager::Handler';

sub new {
  my ($class, $text, $error, $thumb) = @_;

  my %format =
    (
     jpegquality => 90,
     gif_interlace => 0,
     transp => 'threshold',
     tr_threshold => 127,
     tr_errdiff => 'floyd',
     make_colors => 'mediancut',
     translate => 'closest',
     errdiff => 'floyd',
     bgcolor => '000000',
    );

  unless ($text =~ s/^(png|jpeg|gif|tiff|pnm|sgi)(?:,|$)//) {
    $$error = "Missing or invalid format code from format";
    return;
  }
  my $format = $1;

  $class->_build($text, 'format', \%format, $error)
    or return;

  $format{type} = $format;

  bless \%format, $class;
}

sub size {
  my ($self, $width, $height) = @_;

  return ( $width, $height, $self->{type} );
}

sub do {
  my ($self, $work, $write_opts) = @_;

  for my $key (keys %$self) {
    $write_opts->{$key} = $self->{$key};
  }
  
  $work;
}

1;

__END__

=head1 NAME

BSE::Thumb::Imager - thumbnail driver using Imager

=head1 SYNOPSIS

 # bse.cfg
 [editor]
 thumbs_class=BSE::Thumb::Imager

 [imager thumb driver]
 include=path1:path2:path3
 blib=/path/to/imager/src
 jpegquality=90

 [thumb geometries]
 geometryname1=operator1(arguments),operator2(arguments)

=head1 DESCRIPTION

BSE::Thumb::Imager implement's BSE thumbnail interface.  This is used
to implement the various thumbnail tags in the system.

=head1 CONFIGURATION

The following configuration can be set in the [imager thumb driver]
section:

=over

=item *

include - a colon separated list of directories to search for files
used by the different operators.  Default: none.

=item *

blib - if set this will act as a C< use blib 'path'; > for the
supplied path.  Without this your normal Imager installation will be
used.

=item *

jpegquality - the default jpegquality, from 50 to 100.

=back

=head1 OPERATORS

=head2 scale

Syntax: scale(I<size>[c][,fill:I<color>])

I<size> is one of the following forms:

=over

=item *

I<width>xI<height> - the maximum width and height of the new image.

=item *

I<width>x - the maximum width of the image.

=item *

xI<height> - the maximum height of the image.

=item *

I<size> - equivalent to I<size>xI<size>

=back

If the C<c> flag is present the image is scaled the smallest amount
needed to fit one dimension into the provided size.  The other
dimension is then cropped to fit.

If the C<fill:> parameter is present then the provided color is used
to fill out the image to the full size specified.

scale() will never scale an image larger.

eg.

  scale(100x100)
  scale(100x100,fill:red)

=head2 roundcorners

Syntax: roundcorners([radius:I<radii>][bg:I<color>][bgalpha:I<alpha>])

radius (or radii) supplies 1, 2 or 4 values as radii for the corner
rounding:

=over

=item *

if a single radius is supplied, it is the radius for all 4 corners.

=item *

if 2 values are supplied, the first is the radius of the top 2 corners
and the second the radius of the bottom 2 corners.

=item *

if 4 values are supplied they are the radii for the corners as
follows: top left, top right, bottom right, bottom left.

=back

The bg and bgalpha colors are the background color behind the corners.

eg.
  roundcorners(radius:20,bg:FF0000,bgalpha:0)

=head2 mirror

Syntax: mirror(parameters...)

The follow parameters are available:

=over

=item *

height - the height of the mirrored section, either in pixels or as a
percentage.  Default: 30%.

=item *

bg, bgalpha - the background color and alpha.  Default: '000000', 255.

=item *

opacity - the maximum opacity of the mirrored image.  Default: 40%.

=item *

srcx, srcy - transform2() RPN code to calculate the source pixel
position.  Defaults to 'x' and 'y' respectively.

=item *

horizon - distance between the original image and the mirrored image.
Default: 0.

=item *

perspective, perspectiveangle - see the perspective() operator.

=back

eg.

  mirror(height:50,horizon:20,bgalpha:0,opacity:40%)

=head2 sepia

Syntax: sepia([color:I<color>])

Requires that Imager::Filter::Sepia be installed.

Only one parameter is accepted, I<color>, which controls the color of
the output.

eg.

  sepia()

=head2 grey

Syntax: grey()

Converts the image to greyscale.

eg.

  grey()

=head2 filter

Syntax: filter(I<name>,parameters...)

A rough interface to Imager's filter mechanism.

Any parameters supplied to Imager's filter() function.

  filter(gaussian,stddev:2.0)

=head2 conv

Access to Imager's conv filter

Syntax: conv(coefficient,coefficient,...)

eg.

  conv(1,2,1)
  conv(-0.5,2,-0.5)

=head2 border

Adds a border to the image (making it larger).

Syntax: border([width:I<widths>][,bg:I<color>][,bgalpha:I<alpha>])

The width parameter is 1 to 4 border widths which can be in pixels or
percentages:

=over

=item *

1 width is the width for all 4 sides

=item *

if there are 2 widths the first is the top and bottom widths and the
second is the left and right widths.

=item *

if there are 4 widths they are the top, right, bottom and left widths.

=back

C<bg> and C<bgalpha> control the border color.

=head2 rotate

Rotate the image.

Syntax: rotate([angle:I<angle>][,bg:I<color>][,bgalpha:I<alpha>])

Parameters:

=over

=item *

angle - angle of rotation in degrees.  Positive angles are clockwise.

=item *

bg, bgalpha - the color of the "canvas" exposed by the rotation.
Default: '000000', 0 (ie. transparent black)

=back

=head2 perspective

Performs a perspective transformation on the image.

Syntax: perspective(I<amount>[,perspectiveangle:I<angle>][,bg:I<color>][,bgalpha:I<alpha>])

The I<amount> is a small number controlling the perspective effect,
this should typically be abs(I<amount>) < 0.01.  If this is negative
the perspective effect is applied from the right side of the image.

Perspective angle adds an extra shear effect.

bg, bgcolor control the color of the exposed "canvas".

=head2 canvas

Place the image within another image, controlling the background.

Syntax: canvas(I<size>,parameters...)

I<size> can be one of the following:

=over

=item *

I<width>xI<height> - image size

=item *

I<width>x - image will be I<width> wide, and the height from the
original image.

=item *

xI<height> - the image will be I<height> high, and the width from the
original image.

=item *

I<size> - equivlent to I<size>xI<size>.

=back

Each of the above dimensions can be a number of pixels or a percentage
of the original image size.  If either dimension is smaller than the
original image size it it increased to match.

The following other parameters can be supplied:

=over

=item *

bg:I<color>, bgalpha:I<alpha> - controls the background color of the
canvas.  This may be overwritten by the bgfile and bggrad.  Default:
'000000', 255.

=item *

bgfile:I<filename> - an image file to use as a background.  The
behaviour of this is controlled by other parameters.

=item *

bgtile:I<flag> - if this is non-zero then the bgfile image is tiled
over the background, as controlled by bgrepeat, bgxpos, bgypos,
bgrotate.  If this is zero, the default, the bgfile image is scaled
non-proportionally to fit the canvas.

=item *

bgrepeat - controls tiling of the bgfile image, if bgtile is non-zero.
This can be 'none' for no repeats, 'x' for repeating only
horizontally, 'y' for repeating only vertically, or 'both' to repeat
in both directions, the default.

=item *

bgxpos, bgypos - the top left corner of the bgfile tiling.  Either
value can be a percentage.  Default: 0, 0.

=item *

bgrotate - the angle of rotation of the bgfile image when tiling.
This only works well when bgrepeat is 'both'.

=item *

bggrad - the name of a GIMP gradient file to draw over the bgfile and
the bg background.  See the fountain filter in Imager::Filters for
more information.

=item *

gradtype - the type of gradient to draw.  This can be linear,
bilinear, radial, radial_square, revolution, conical.

=item *

gradrepeat - how the gradient should repeat outside the range of
pixels defined by (gradx1, grady1) - (gradx2, grady2).  Options
include none, sawtooth, triangle, saw_both, tri_both.

=item *

gradx1, grady1, gradx2, grady2 - defines the interval on the image
specifying the direction and position of the gradient.  These can be
in pixels or a percentage of the width/height of the canvas.  Default:
0, 0, 100%, 100%.

=item *

xpos, ypos - the position of the original image on the canvas.  This can be in pixels or a percentage.  Default: 50%, 50%.

=back

=head2 format

Controls the format of the output file.

Syntax: format(I<type>,[write-parameters])

I<type> can be any one of png, jpeg, gif, tiff, pnm, sgi, but will
typically be one of the first 3.

Possible write parameters include:

=over

=item *

jpegquality - output quality for jpeg files.  Default: 90.

=item *

gif_interlace - set to 1 to produce interlaced GIFs.

=item *

transp - control transparency handle for GIF.  Default: threshold.

=item *

tr_threshold - threshold for whether a pixel should be treated as
transparent for GIF images.

=item *

tr_errdiff - the type of error diffusion to perform on the alpha
channel for GIF images.

=item *

make_colors - how to build the color table for GIF images.

=item *

translate - how to translate the colors to the color table for GIF
images.

=item *

errdiff - the type of error diffustion to perform if translate is
errdiff.

=item *

bgcolor - the background color to overlay on if the source image has
an alpha channel and the output format is jpeg.

=back

=cut
