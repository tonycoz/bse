package BSE::TagFormats;
use strict;
use DevHelp::HTML;

sub _format_image {
  my ($self, $im, $align, $rest) = @_;

  if ($align && exists $im->{$align}) {
    if ($align eq 'src') {
      return escape_html($im->image_url($self->{cfg}));
    }
    else {
      return escape_html($im->{$align});
    }
  }
  else {
    return $im->formatted
      (
       cfg => $self->{cfg},
       align => $align,
       extras => $rest,
      );
  }
}

sub _format_file {
  my ($self, $file, $field) = @_;

  defined $field or $field = '';

  if ($field && exists $file->{$field}) {
    return escape_html($file->{$field});
  }
  else {
    my $url = "/cgi-bin/user.pl?download_file=1&file=$file->{id}";
    my $eurl = escape_html($url);
    if ($field eq 'url') {
      return $eurl;
    }
    my $class = $file->{download} ? "file_download" : "file_inline";
    my $html = qq!<a class="$class" href="$eurl">! . escape_html($file->{displayName}) . '</a>';
    return $html;
  }
}

1;
