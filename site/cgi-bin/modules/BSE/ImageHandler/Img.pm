package BSE::ImageHandler::Img;
use strict;
use base 'BSE::ImageHandler::Base';
use Carp qw(confess);
use DevHelp::HTML;

sub thumb_base_url {
  '/cgi-bin/thumb.pl';
}

sub format {
  my ($self, %opts) = @_;

  my $im = delete $opts{image}
    or confess "Missing image parameter";

  my $cfg = $self->cfg;
  my $align = delete $opts{align} || '';
  my $rest = delete $opts{extras} || '';
  my $url = delete $opts{url};

  my $image_url = $im->image_url($cfg);
  my $html = qq!<img src="$image_url" width="$im->{width}"!
    . qq! height="$im->{height}" alt="! . escape_html($im->{alt})
      . qq!"!;
  $html .= qq! align="$align"! if $align && $align ne '-';
  my $xhtml = $cfg->entry("basic", "xhtml", 1);
  unless ($xhtml) {
    unless (defined($rest) && $rest =~ /\bborder=/i) {
      $html .= ' border="0"' ;
    }
  }
  defined $rest or $rest = '';
  # remove any non-img options
  $rest =~ s/\w+:\w+=(?:(["'])[^"']*\1|\S+)//g;
  $rest =~ /\bclass=/ or $rest .= ' class="bse_image_tag"';

  $html .= " $rest" if $rest;
  $html .= qq! />!;
  $url ||= $im->{url};
  if ($url) {
    $url = escape_html($url);
    $html = qq!<a href="$url">$html</a>!;
  }

  return $html;
}

sub inline {
  my ($self, %opts) = @_;

  my $image = delete $opts{image}
    or confess "Missing image parameter";
  my $align = delete $opts{align}
    or confess "Missing align parameter";

  my $xhtml = $self->cfg->entry("basic", "xhtml", 1);

  my $image_url = $image->image_url($self->{cfg});
  my $html;
  if ($xhtml) {
    $html = qq!<img src="$image_url"!
      .qq! width="$image->{width}" height="$image->{height}"!
	.qq! alt="$image->{alt}" class="bse_image_$align" />!;
  }
  else {
    $html = qq!<img src="$image_url"!
      .qq! width="$image->{width}" height="$image->{height}" border="0"!
	.qq! alt="$image->{alt}" align="$align" hspace="10" vspace="10" />!;
  }
  if ($image->{url}) {
    $html = qq!<a href="$image->{url}">$html</a>!;
  }
  
  return $html;
}

sub _make_thumb_hash {
  my ($self, $geo_id, $im, $static) = @_;

  my $cfg = $self->cfg;
  my $debug = $cfg->entry('debug', 'thumbnails', 0);

  $static ||= 0;

  $debug
    and print STDERR "_make_thumb_hash(..., $geo_id, $im->{src}, ..., $static)\n";

  $geo_id =~ /^[\w,]+$/
    or return ( undef, "* invalid geometry id *" );

  my $geometry = $cfg->entry('thumb geometries', $geo_id)
    or return ( undef, "* cannot find thumb geometry $geo_id *" );

  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or return ( undef, '* no thumbnail engine configured *' );

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);

  $debug
    and print STDERR "  Thumb class $thumbs_class\n";

  my $error;
  $thumbs->validate_geometry($geometry, \$error)
    or return ( undef, "* invalid geometry string: $error *" );

  my %im = map { $_ => $im->{$_} } $im->columns;
  my $base = $self->thumb_base_url;

  @im{qw/width height type original/} = 
    $thumbs->thumb_dimensions_sized($geometry, @$im{qw/width height/});

  my $do_cache = $cfg->entry('basic', 'cache_thumbnails', 1);
  $im{image} = '';
  if ($im{original}) {
    $debug
      and print STDERR "  Using original\n";
    $im{image} = $im->{src};
  }
  elsif ($static && $do_cache) {
    require BSE::Util::Thumb;
    ($im{image}) = BSE::Util::Thumb->generate_thumb($cfg, $im, $geo_id, $thumbs);
    $debug
      and print STDERR "  Generated $im{image}\n";
  }
  unless ($im{image}) {
    $im{image} = "$base?g=$geo_id&page=$im->{articleId}&image=$im->{id}";

    if (defined $im{type}) {
      $im{image} .= "&type.$im{type}";
    }
    else {
      $im{image} .= "&" . $im->{image};
    }


    $debug
      and print STDERR "  Defaulting to dynamic thumb url $im{image}\n";
  }
  $im{src} = $im{image};

  return \%im;
}

sub thumb {
  my ($self, %opts) = @_;

  my $geo_id = delete $opts{geo};
  defined $geo_id 
    or confess "Missing geo parameter";
  my $im = delete $opts{image}
    or confess "Missing image parameter";
  my $field = delete $opts{field} || '';
  my $static = delete $opts{static} || 0;
  my $cfg = $self->cfg;

  my ($imwork, $error) = 
    $self->_make_thumb_hash($geo_id, $im, $static);

  $imwork
    or return escape_html($error);
  
  if ($field) {
    my $value = $imwork->{$field};
    defined $value or $value = '';
    return escape_html($value);
  }
  else {
    my $class = $cfg->entry('thumb classes', $geo_id, "bse_image_thumb");
    my $xhtml = $cfg->entry("basic", "xhtml", 1);
    my $html = '<img src="' . escape_html($imwork->{src}) . '" alt="' . escape_html($imwork->{alt}) . qq!" width="$imwork->{width}" height="$imwork->{height}"!;
    $html .= qq! border="0"! unless $xhtml;
    if ($class) {
      $html .= qq! class="$class"!;
    }
    $html .= ' />';
    if ($imwork->{url}) {
      $html = '<a href="' . escape_html($imwork->{url}) . '">' . $html . "</a>";
    }
    return $html;
  }
}

1;
