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

sub html_type {
  my ($class, $cfg) = @_;

  my $type = "text/html";
  my $charset = $cfg->entry('html', 'charset');
  $charset = 'iso-8859-1' unless defined $charset;
  return $type . "; charset=$charset";
}

sub show_page {
  my ($class, $template, $cfg, $acts) = @_;

  my $type = $class->html_type($cfg);

  print "Content-Type: $type\n\n";
  print $class->get_page($template, $cfg, $acts);
}

sub get_response {
  my ($class, $template, $cfg, $acts) = @_;

  my $result =
    {
     type => $class->html_type($cfg),
     content => scalar($class->get_page($template, $cfg, $acts)),
    };
  push @{$result->{headers}}, "Content-Length: ".length($result->{content});

  $result;
}

sub get_refresh {
  my ($class, $url, $cfg) = @_;

  return
    {
     type=>$class->html_type($cfg),
     content=>"<html></html>",
     headers=>[ qq/Refresh: 0; url="$url"/ ],
    };
}

1;
