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

  return $file->inline
    (
     cfg => $self->cfg,
     field => $field
    );
}

1;
