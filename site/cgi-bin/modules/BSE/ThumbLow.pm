package BSE::ThumbLow;
use strict;
use DevHelp::HTML;

sub thumb_base_url {
  '/cgi-bin/thumb.pl';
}

sub _make_thumb_hash {
  my ($self, $geo_id, $im, $cfg, $static) = @_;

  my $debug = $cfg->entry('debug', 'thumbnails', 0);

  $static ||= 0;

  $debug
    and print STDERR "_make_thumb_hash(..., $geo_id, $im->{src}, ..., $static)\n";

  $geo_id =~ /^[\w,]+$/
    or return ( undef, "** invalid geometry id **" );

  my $geometry = $cfg->entry('thumb geometries', $geo_id)
    or return ( undef, "** cannot find thumb geometry $geo_id**" );

  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or return ( undef, '** no thumbnail engine configured **' );

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);

  $debug
    and print STDERR "  Thumb class $thumbs_class\n";

  my $error;
  $thumbs->validate_geometry($geometry, \$error)
    or return ( undef, "** invalid geometry string: $error **" );

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

sub _thumbimage_low {
  my ($self, $geo_id, $im, $field, $cfg, $static) = @_;

  my ($imwork, $error) = 
    $self->_make_thumb_hash($geo_id, $im, $cfg, $static);
  
  if ($field) {
    my $value = $imwork->{$field};
    defined $value or $value = '';
    return escape_html($value);
  }
  else {
    my $class = $cfg->entry('thumb classes', $geo_id);
    my $html = '<img src="' . escape_html($imwork->{src}) . '" alt="' . escape_html($imwork->{alt}) . qq!" width="$imwork->{width}" height="$imwork->{height}" border="0"!;
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
