package BSE::Util::Iterate;
use strict;
use base 'DevHelp::Tags::Iterate';
use DevHelp::HTML;

sub escape {
  escape_html($_[1]);
}

1;
