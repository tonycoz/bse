package BSE::Thumb::Imager;
use strict;
#use blib '/home/tony/dev/imager/maint/Imager/';
use Imager;

sub new {
  my ($class, $cfg) = @_;
  
  return bless { cfg => $cfg }, $class;
}

sub _width_height {
  my ($self, $image, $max_width, $max_height, $max_pixels) = @_;

  # figure out a scale size
  my $cfg = $self->{cfg};
  $max_pixels ||= $cfg->entry('thumbnails', 'max_pixels', 50000);
  $max_pixels = 100 if $max_pixels < 100;
  $max_width ||= $cfg->entry('thumbnails', 'max_width', 200);
  $max_width = 10 if $max_width < 10;
  $max_height ||= $cfg->entry('thumbnails', 'max_height', 200);
  $max_height = 10 if $max_height < 10;

  my $width = $image->{width};
  my $height = $image->{height};
  if ($width > $max_width) {
    $width = $max_width;
    $height = $height * $max_width / $image->{width};
  }
  if ($height > $max_height) {
    my $old_height = $height;
    $height = $max_height;
    $width = $width * $max_height / $old_height;
  }

  if ($width * $height > $max_pixels) {
    my $scale  = ($max_pixels * 1.0 / $width / $height) ** 0.5;
    $width *= $scale;
    $height *= $scale;
  }

  return ($width == $image->{width} && $height == $image->{height}, 
	  int($width), int($height));
}

# returns (width, height) as a list
sub thumb_dimensions {
  my ($self, $image_filename, $image, $max_width, $max_height, $max_pixels) = @_;

  my $im = Imager->new();

  # as long as we can read it
  unless ($im->read(file=>$image_filename)) {
    print STDERR "Error reading image '$image_filename' for thumb calculations: ",
      $im->errstr,"\n";
    return;
  }


  return $self->_width_height($image, $max_width, $max_height, $max_pixels);
}

# returns (content type, image data) as a list
sub thumb_data {
  my ($self, $image_filename, $image, $max_width, $max_height, 
      $max_pixels) = @_;

  my ($use_orig, $width, $height) = 
    $self->_width_height($image, $max_width, $max_height, $max_pixels);

  my $im = Imager->new();

  unless ($im->read(file=>$image_filename)) {
    print STDERR "Error reading image  '$image_filename' for thumb calculations: ",
      $im->errstr,"\n";
    return;
  }

  
  my $out;
  if ($use_orig) {
    $out = $im;
  }
  else {
    my $qtype = $Imager::VERSION >= 0.54 ? 'mixing' : 'normal';
    $out = $im->scale(xpixels => $width, ypixels=>$height, qtype => $qtype);
  }

  my $type = 'jpeg';
  if ($image_filename =~ /\.(gif|png)$/i
     || ($out->getchannels != 3 && $out->getchannels != 1)) {
    $type = 'png';
  }

  my $data;
  unless ($out->write(data => \$data, type=>$type)) {
    print STDERR "Error writing: ",$out->errstr,"\n";
  }

  return ("image/$type", $data);
}

1;
