package BSE::Arrows;
use strict;
use DevHelp::HTML;

use base 'Exporter';

use vars qw(@EXPORT);

@EXPORT = qw(make_arrows);

sub make_arrows {
  my ($cfg, $down_url, $up_url, $refresh, $type, %opts) = @_;

  my $section = $type ? "$type arrows" : "arrows";
  my $prefix = $cfg->entry($section, "prefix", $type);

  my $images_uri = $cfg->entry('uri', 'images', '/images');
  my $html = '';
  my $want_xhtml = $cfg->entryBool('basic', 'xhtml', 1);
  my $extra_attr = "";
  unless ($want_xhtml) {
    my $align = $cfg->entry('arrows', 'align', $want_xhtml ? 'bottom' : 'absbottom');
    $extra_attr = qq(border="0" align="$align" );
  }
  if ($cfg->entry($section, "set_size", 
		  $cfg->entry("arrows", "set_size", 1))) {
    my $image_width = $cfg->entry($section, "image_width", 17);
    my $image_height = $cfg->entry($section, "image_height", 13);
    $extra_attr .= qq(width="$image_width" height="$image_height" );
  }

  my $nomove = qq'<img src="/images/trans_pixel.gif" alt="" $extra_attr/>';
  if ($down_url) {
    my $down_img = $cfg->entry($section, "downimg", "$images_uri/admin/${prefix}move_down.gif");
    $down_url .= "&r=".escape_uri($refresh) if $refresh;
    $down_url = escape_html($down_url);
    my $alt = escape_html($cfg->entry($section, "down_arrow_text", $cfg->entry('arrows', 'down_arrow_text', "Move Down")));
    $html .= qq!<a href="$down_url">!;
    $html .= qq!<img src="$down_img" alt="$alt" $extra_attr/></a>!;
  }
  else {
    $html .= $nomove;
  }
  if ($up_url) {
    my $up_img = $cfg->entry($section, "upimg", "$images_uri/admin/${prefix}move_up.gif");
    $up_url .= "&r=".escape_uri($refresh) if $refresh;
    $up_url = escape_html($up_url);
    my $alt = escape_html($cfg->entry($section, "up_arrow_text", $cfg->entry('arrows', 'up_arrow_text', "Move Up")));
    $html .= qq!<a href="$up_url">!;
    $html .= qq!<img src="$up_img" alt="$alt" $extra_attr/></a>!;
  }
  else {
    $html .= $nomove;
  }
  my $class = $cfg->entry($section, "class", $cfg->entry("arrows", "class", "bse_arrows"));

  my $tag = $cfg->entry($section, "tag", $cfg->entry("arrows", "tag", "span"));
  my $wrapper = qq(<$tag class="$class");
  if ($opts{id}) {
    my $id_prefix = $cfg->entry($section, "idprefix", $opts{id_prefix} || $prefix);
    $wrapper .= qq( id="${id_prefix}$opts{id}");
  }
  $html = "$wrapper>$html</$tag>";

  $html;
}

1;
