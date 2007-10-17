package BSE::ThumbLow;
use strict;
use DevHelp::HTML;

sub thumb_base_url {
  '/cgi-bin/thumb.pl';
}

sub _thumbimage_low {
  my ($self, $geo_id, $im, $field, $cfg) = @_;

  $geo_id =~ /^[\w,]+$/
    or return "** invalid geometry id **";

  my $geometry = $cfg->entry('thumb geometries', $geo_id)
    or return "** cannot find thumb geometry $geo_id**";

  my $thumbs_class = $cfg->entry('editor', 'thumbs_class')
    or return '** no thumbnail engine configured **';

  (my $thumbs_file = $thumbs_class . ".pm") =~ s!::!/!g;
  require $thumbs_file;
  my $thumbs = $thumbs_class->new($cfg);

  my $error;
  $thumbs->validate_geometry($geometry, \$error)
    or return "** invalid geometry string: $error **";

  my %im = map { $_ => $im->{$_} } $im->columns;
  my $base = $self->thumb_base_url;

  @im{qw/width height alpha original/} = 
    $thumbs->thumb_dimensions_sized($geometry, @$im{qw/width height/});

  if ($im{original}) {
    $im{image} = "/images/" . $im->{image};
  }
  else {
    $im{image} = "$base?g=$geo_id&page=$im->{articleId}&image=$im->{id}";

    # hack for IE6
    $im{alpha} 
      and $im{image} .= '&alpha-trans.png';
  }
  
  if ($field) {
    my $value = $im{$field};
    defined $value or $value = '';
    return escape_html($value);
  }
  else {
    my $class = $cfg->entry('thumb classes', $geo_id);
    my $html = '<img src="' . escape_html($im{image}) . '" alt="' . escape_html($im{alt}) . qq!" width="$im{width}" height="$im{height}" border="0"!;
    if ($class) {
      $html .= qq! class="$class"!;
    }
    $html .= ' />';
    if ($im{url}) {
      $html = '<a href="' . escape_html($im{url}) . '">' . $html . "</a>";
    }
    return $html;
  }
}

1;
