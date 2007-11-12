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
  my ($self, $geometry, $width, $height) = @_;

  my $error;
  my $geolist = $self->_parse_geometry($geometry, \$error)
    or return;

  my $req_alpha = 0;
  my $use_original = 1;

  for my $geo (@$geolist) {
    my ($can_original, $this_alpha);

    ($width, $height, $this_alpha, $can_original)
      = $geo->size($width, $height);

    $req_alpha ||= $req_alpha;
    $use_original &&= $can_original;
  }

  return ($width, $height, $req_alpha, $use_original);
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

  my $work = $src;
  for my $geo (@$geolist) {
    $work = $geo->do($work);
  }

  my $data;
  my $type = $src->tags(name => 'i_format');

  if ($work->getchannels == 4 || $work->getchannels == 2) {
    $type = 'png';
  }
  
  unless ($work->write(data => \$data, type => $type, jpegquality => 90)) {
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
      
      bless \%geo, $class;
}

sub size {
  my ($self, $width, $height) = @_;

  return ( $width, $height, $self->{bgalpha} != 255 );
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

  return ( $width, $height, $geo->{bgalpha} != 255 );
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

  $class->_build($text, 'filter', \%filter, $error)
    or return;

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
    $border{left} = $border{right} = $widths[0];
    $border{top} = $border{bottom} = $widths[1];
  }
  elsif (@widths == 4) {
    @border{qw/left right top bottom/} = @widths;
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

  return ( $width, $height, $geo->{bgalpha} != 255 );
}

sub do {
  my ($border, $work) = @_;

  $work = $work->convert(preset => 'rgb')
    if $work->getchannels < 3;
  my $channels = $work->getchannels;
  $border->{bgalpha} != 255 and $channels = 4;
  my $left = $border->_percent_of_rounded($border->{left}, $work->getwidth);
  my $right = $border->_percent_of_rounded($border->{right}, $work->getwidth);
  my $top = $border->_percent_of_rounded($border->{top}, $work->getheight);
  my $bottom = $border->_percent_of_rounded($border->{bottom}, $work->getheight);

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
  
  return ($width, $height, $geo->{bgalpha});
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

  return ( $width, $height, $geo->{bgalpha} != 255 );
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
    $base >= $max and return 0;
    return $self->_percent_of_rounded($spec, $max-$base);
  }
  else {
    return $spec;
  }
}

sub size {
  my ($self, $width, $height) = @_;

  my $want_width = $self->_calc_dim($width, $self->{width});
  my $want_height = $self->_calc_dim($height, $self->{height});
  my $want_xpos = $self->_calc_pos($self->{xpos}, $width, $want_width);
  my $want_ypos = $self->_calc_pos($self->{ypos}, $height, $want_height);

  if ($width == $want_width && $height == $want_height
      && $want_xpos == 0 && $want_ypos == 0) {
    # original image
    return ( $width, $height, 0, 1 );
  }

  $width < $want_width and $width = $want_width;
  $height < $want_height and $height = $want_height;

  return ( $width, $height, $self->{bgalpha} != 255 );
}

sub do {
  my ($self, $work) = @_;

  if ($work->getchannels < 3) {
    $work = $work->convert(preset => 'rgb');
  }

  my $bg = $self->_bgcolor;

  my $width = $work->getwidth;
  my $height = $work->getheight;
  my $want_width = $self->_calc_dim($width, $self->{width});
  my $want_height = $self->_calc_dim($height, $self->{height});
  my $want_xpos = $self->_calc_pos($self->{xpos}, $width, $want_width);
  my $want_ypos = $self->_calc_pos($self->{ypos}, $height, $want_height);

  $width < $want_width and $width = $want_width;
  $height < $want_height and $height = $want_height;
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
      my $xpos = $self->_calc_dim($want_width, $self->{bgxpos});
      my $ypos = $self->_calc_dim($want_height, $self->{bgypos});
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
      $out->box(fill => { image => $bg, matrix => $matrix }, %opts);
    }
    else {
      if ($bg->getwidth != $want_width || $bg->getheight != $want_height) {
	$bg = $bg->scale(xpixels => $want_width, ypixels => $want_height,
			 qtype => 'mixing', type => 'nonprop');
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

1;
