package Squirrel::ImageEditor;
#use CGI 'param';
use strict;
use Constants qw($URLBASE $TMPLDIR %TEMPLATE_OPTS);

sub new {
  my ($class, %opts) = @_;
  $opts{message} = '';
  $opts{template} ||= 'admin/article_img.tmpl';
  return bless \%opts, $_[0];
}

my @actions = qw(artimg addimg showimages process);

sub action {
  my ($self, $query) = @_;

  for my $action (@actions) {
    if (defined $query->param($action)) {
      $self->$action($query);
      return 1;
    }
  }
  for my $param ($query->param()) {
    if ($param =~ /^removeimg_(\d+)/) {
      $self->remove_img($query, $1);
      return 1;
    }
    if ($param =~ /^moveimgup_(\d+)/) {
      $self->moveup($query, $1);
      return 1;
    }
    if ($param =~ /^moveimgdown_(\d+)/) {
      $self->movedown($query, $1);
      return 1;
    }
  }

  return 0;
}

sub set {
  my ($self, $images, $image_pos) = @_;

  $self->{session}{images} = [ @$images ];
  $self->{session}{imagePos} = $image_pos;
}

sub clear {
  my $self = shift;
  #print STDERR "clear\n";
  delete @{$self->{session}}{qw/images imagePos/};
}

sub images {
  my $self = shift;

  return @{$self->{session}{images} || []};
}

sub imagePos {
  my $self = shift;
  
  return $self->{session}{imagePos} || 'tr';
}

sub artimg {
  my ($self, $query) = @_;
  $self->images_update($query);
  $self->page();
}

sub showimages {
  my ($self, $query) = @_;
  $self->artimg($query);
}

sub process {
  my ($self, $query) = @_;
  $self->artimg($query);
}

# handle any changes the user made
sub images_update {
  my ($self, $query) = @_;
  my $imagePos = $query->param('imagePos');
  my $old = $self->imagePos();
  if (defined($imagePos) && $imagePos ne $old) {
    $self->{session}{imagePos} = $imagePos;
  }

  my @images = $self->images();
  my @alt = $query->param('alt');
  if (@alt) {
    for my $index (0 .. $#images) {
      $images[$index]{alt} = $alt[$index];
    }
  }
  my @urls = $query->param('url');
  if (@urls) {
    for my $index (0 .. $#images) {
      $images[$index]{url} = $urls[$index];
    }
  }

  #my @order = $query->param('order');
  #if (@order) {
  #  my @indexes = sort { $order[$a] <=> $order[$b]
  #			   || $a <=> $b
  #			 } 0..$#images;
  #  @images = @images[@indexes];
  #}

  # regenerate the order field
  for my $index (0 .. $#images) {
    $images[$index]{order} = $index;
  }
  $self->{session}{images} = \@images;

  return @images;
}

# add an image
sub addimg {
  my ($self, $query) = @_;
  my @images = $self->images_update($query);

  unless ($query->param('image')) {
    $self->{message} = "Enter or select the name of an image file on your machine.";
    $self->showimages($query);
    return;
  }
  if (-z $query->param('image')) {
    $self->{message} = "Image file is empty";
    $self->showimages($query);
    return;
  }

  my $image = $query->param('image');

  my $basename = '';
  $image =~ /([\w.-]+)$/ and $basename = $1;

  # create a filename that we hope is unique
  my $filename = time. '_'. $basename;

  # for the sysopen() constants
  use Fcntl;

  use Constants '$IMAGEDIR';

  # loop until we have a unique filename
  my $counter="";
  $filename = time. '_' . $counter . '_' . $basename 
    until sysopen( OUTPUT, "$IMAGEDIR/$filename", O_WRONLY| O_CREAT| O_EXCL)
      || ++$counter > 100;

  fileno(OUTPUT) or die "Could not open image file: $!";

  # for OSs with special text line endings
  binmode OUTPUT;

  my $buffer;

  no strict 'refs';

  # read the image in from the browser and output it to our output filehandle
  print OUTPUT $buffer while read $image, $buffer, 1024;

  # close and flush
  close OUTPUT
    or die "Could not close image file $filename: $!";

  use Image::Size;

  my($width,$height) = imgsize("$IMAGEDIR/$filename");

  push(@images, { image=>$filename, alt=>$query->param('altIn'), height=>$height, 
		  width=>$width, url=>$query->param('url') });

  $self->{session}{images} = \@images;
  my $url = $self->_fix_url($query, "$URLBASE$ENV{SCRIPT_NAME}?showimages=");
  print  "Refresh: 0; url=\"$url\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
}

# remove an image
sub remove_img {
  my ($self, $query, $index) = @_;
  my @images = $self->images();
  my ($image) = splice(@images, $index, 1);
  unlink "$IMAGEDIR$image->{image}" if !$image->{id};
  $self->{session}{images} = \@images;

  my $url = $self->_fix_url($query, "$URLBASE$ENV{SCRIPT_NAME}?showimages=");
  print  "Refresh: 0; url=\"$url\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
}

# move an image up (swap it with the previous image)
sub moveup {
  my ($self, $query, $index) = @_;
  my @images = $self->images;
  if ($index > 0 && $index < @images) {
    @images[$index-1, $index] = @images[$index, $index-1];
    $self->{session}{images} = \@images;
  }

  my $url = $self->_fix_url($query, "$URLBASE$ENV{SCRIPT_NAME}?showimages=");
  print  "Refresh: 0; url=\"$url\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
}

# move an image down (swap it with the next image)
sub movedown {
  my ($self, $query, $index) = @_;
  my @images = $self->images;
  if ($index >= 0 && $index < $#images) {
    @images[$index+1, $index] = @images[$index, $index+1];
    $self->{session}{images} = \@images;
  }

  my $url = $self->_fix_url($query, "$URLBASE$ENV{SCRIPT_NAME}?showimages=");
  print  "Refresh: 0; url=\"$url\"\n";
  print "Content-type: text/html\n\n<HTML></HTML>\n";
}

sub _fix_url {
  my ($self, $query, $url) = @_;
  if ($self->{keep}) {
    for my $key (@{$self->{keep}}) {
      for my $value ($query->param($key)) {
	$url .= '&' . $key . '=' . CGI::escape($value);
      }
    }
  }

  return $url;
}

sub page {
  my ($self) = @_;

  my @images = $self->images;
  my $image_index = -1;
  my $imagePos = $self->imagePos;
  my %acts;
  %acts =
    (
     message=>sub { $self->{message} },
     script => sub { $ENV{SCRIPT_NAME} },
     iterate_image => sub { ++$image_index < @images },
     image => sub { $images[$image_index]{$_[0]} },
     checked => sub { $imagePos eq $_[0] ? ' checked' : '' },
     imgtype => sub { $self->{imgtype} },
     imgmove =>
     sub {
       my $html = '';
       if ($image_index > 0) {
	 $html .= <<HTML;
<input type=submit name="moveimgup_$image_index" value="Move Up">
HTML
       }
       if ($image_index < $#images) {
	 $html .= <<HTML;
<input type=submit name="moveimgdown_$image_index" value="Move Down">
HTML
       }
       if ($html eq '') {
         $html = '&nbsp;';
       }
       return $html;
     },
    );
  if ($self->{extras}) {
    for my $key (keys %{$self->{extras}}) {
      $acts{$key} = $self->{extras}{$key}
	unless exists $acts{$key};
    }
  }
  print "Content-Type: text/html\n\n";
  print Squirrel::Template->new(%TEMPLATE_OPTS)
    ->show_page($TMPLDIR, $self->{template}, \%acts);
}

1;
