package BSE::Template;
use strict;
use Constants qw/$TMPLDIR/;
use Squirrel::Template;

sub get_page {
  my ($class, $template, $cfg, $acts) = @_;

  my $base = $cfg->entry('paths', 'templates') 
    || $TMPLDIR;
  my $file = $cfg->entry('templates', $template) || "$template.tmpl";

  my $obj = Squirrel::Template->new(template_dir => $base);

  $obj->show_page($base, $file, $acts);
}

sub show_page {
  my ($class, $template, $cfg, $acts) = @_;

  my $type = "text/html";
  my $charset = $cfg->entry('html', 'charset');
  $charset = 'iso-8859-1' unless defined $charset;
  $type .= "; charset=$charset";

  print "Content-Type: $type\n\n";
  print $class->get_page($template, $cfg, $acts);
}

1;
