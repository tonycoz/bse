package BSE::TagFormats;
use strict;
use DevHelp::HTML;

sub image_url {
  my ($self, $im) = @_;

  $im->{src} || "/images/$im->{image}";
}

sub _format_image {
  my ($self, $im, $align, $rest) = @_;

  if ($align && exists $im->{$align}) {
    if ($align eq 'src') {
      return escape_html($self->image_url($im));
    }
    else {
      return escape_html($im->{$align});
    }
  }
  else {
    my $image_url = $self->image_url($im);
    my $html = qq!<img src="$image_url" width="$im->{width}"!
      . qq! height="$im->{height}" alt="! . escape_html($im->{alt})
	     . qq!"!;
    $html .= qq! align="$align"! if $align && $align ne '-';
    my $xhtml = $self->{cfg}->entry("basic", "xhtml", 1);
    unless ($xhtml) {
      unless (defined($rest) && $rest =~ /\bborder=/i) {
	$html .= ' border="0"' ;
      }
    }
    defined $rest or $rest = '';
    $rest =~ /\bclass=/ or $rest .= ' class="bse_image_tag"';

    $html .= " $rest" if $rest;
    $html .= qq! />!;
    if ($im->{url}) {
      $html = qq!<a href="$im->{url}">$html</a>!;
    }
    return $html;
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
