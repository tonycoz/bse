package BSE::FileHandler::Default;
use strict;
use base "BSE::FileHandler::Base";
use DevHelp::HTML;

sub process_file {
  my ($self, $file) = @_;

  # accept the file, but do nothing

  1;
}

sub inline {
  my ($self, $file) = @_;

  my $url = $file->url($self->cfg);
  my $eurl = escape_html($url);
  my $class = $file->{download} ? "file_download" : "file_inline";
  my $html = qq!<a class="$class" href="$eurl">! . escape_html($file->{displayName}) . '</a>';
  return $html;
}

sub metaprefix {
  "def"
}

1;
