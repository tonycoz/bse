package BSE::Arrows;
use strict;
use DevHelp::HTML;

use base 'Exporter';

use vars qw(@EXPORT);

@EXPORT = qw(make_arrows);

sub make_arrows {
  my ($cfg, $down_url, $up_url, $refresh, $prefix) = @_;

  my $images_uri = $cfg->entry('uri', 'images', '/images');
  my $html = '';
  my $want_xhtml = $cfg->entryBool('basic', 'xhtml', 1);
  my $align = $cfg->entry('arrows', 'align', $want_xhtml ? 'bottom' : 'absbottom');
  my $nomove = qq'<img src="/images/trans_pixel.gif" width="17" height="13" border="0" align="$align" alt="" />';
  if ($down_url) {
    $down_url .= "&r=".escape_uri($refresh) if $refresh;
    $down_url = escape_html($down_url);
    my $alt = escape_html($cfg->entry('arrows', 'down_arrow_text', "Move Down"));
    $html .= qq!<a href="$down_url">!;
    $html .= qq!<img src="$images_uri/admin/${prefix}move_down.gif" !
      . qq!width="17" height="13" alt="$alt" border="0" align="$align" /></a>!;
  }
  else {
    $html .= $nomove;
  }
  if ($up_url) {
    $up_url .= "&r=".escape_uri($refresh) if $refresh;
    $up_url = escape_html($up_url);
    my $alt = escape_html($cfg->entry('arrows', 'up_arrow_text', "Move Up"));
    $html .= qq!<a href="$up_url">!;
    $html .= qq!<img src="$images_uri/admin/${prefix}move_up.gif" !
      . qq!width="17" height="13" alt="$alt" border="0" align="$align" /></a>!;
  }
  else {
    $html .= $nomove;
  }
}

1;
