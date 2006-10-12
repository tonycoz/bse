package BSE::Template;
use strict;
use Squirrel::Template;
use Carp 'confess';

sub get_page {
  my ($class, $template, $cfg, $acts, $base_template) = @_;

  my @dirs = $class->template_dirs($cfg);
  my $file = $cfg->entry('templates', $template) || $template;
  $file =~ /\.\w+$/ or $file .= ".tmpl";

  
  my $obj = Squirrel::Template->new(template_dir => \@dirs);

  my $out;
  if ($base_template) {
    eval {
      $out = $obj->show_page(undef, $file, $acts);
    };
    if ($@) {
      if ($@ =~ /Cannot find template/) {
	print STDERR "Could not find requested template $file, trying $base_template\n";
	$file = $cfg->entry('templates', $base_template) || $base_template;
	$file =~ /\.\w+$/ or $file .= ".tmpl";
	$out = $obj->show_page(undef, $file, $acts);
      }
      else {
	print STDERR "** Eval error: $@\n";
	$out = "<html><body>There was an error producing this page - please contect the webmaster.</body></html>\n";
      }
    }
  }
  else {
    $out = $obj->show_page(undef, $file, $acts);
  }
    

  $out;
}

sub replace {
  my ($class, $source, $cfg, $acts) = @_;

  my @dirs = $class->template_dirs($cfg);
  my $obj = Squirrel::Template->new(template_dir => \@dirs);

  $obj->replace_template($source, $acts);
}

sub html_type {
  my ($class, $cfg) = @_;

  my $type = "text/html";
  my $charset = $cfg->entry('html', 'charset');
  $charset = 'iso-8859-1' unless defined $charset;
  return $type . "; charset=$charset";
}

sub get_type {
  my ($class, $cfg, $template) = @_;

  return $cfg->entry("template types", $template)
    || $class->html_type($cfg);
}

sub show_page {
  my ($class, $template, $cfg, $acts, $base_template) = @_;

  $class->show_literal($class->get_page($template, $cfg, $acts, $base_template), $cfg);
}

sub show_replaced {
  my ($class, $source, $cfg, $acts) = @_;

  $class->show_literal($class->replace($source, $cfg, $acts), $cfg);
}

sub show_literal {
  my ($class, $text, $cfg) = @_;

  my $type = $class->html_type($cfg);

  print "Content-Type: $type\n\n";
  print $text;
}

sub get_response {
  my ($class, $template, $cfg, $acts, $base_template) = @_;

  my $result =
    {
     type => $class->get_type($cfg, $template),
     content => scalar($class->get_page($template, $cfg, $acts, $base_template)),
    };
  push @{$result->{headers}}, "Content-Length: ".length($result->{content});

  $result;
}

sub get_refresh {
  my ($class, $url, $cfg) = @_;


  return
    {
     content => '',
     headers => [ 
		 "Location: $url",
		 "Status: 302"
		],
    };

  # the commented out headers were meant to help Opera, but they didn't
  return
    {
     type=>$class->html_type($cfg),
     content=>"<html></html>",
     headers=>[ qq/Refresh: 0; url=$url/,
		#qq/Cache-Control: no-store, no-cache, must-revalidate, post-check=0, pre-check=0, max-age=0/,
		#qq/Pragma: no-cache/,
		#qq/Expires: Thu, 01 Jan 1970 00:00:00 GMT/
	      ],
    };
}

sub template_dirs {
  my ($class, $cfg) = @_;

  ref($cfg) eq 'BSE::Cfg'
    or confess "Invalid cfg $cfg supplied\n";

  my $base = $cfg->entryVar('paths', 'templates');
  my $local = $cfg->entry('paths', 'local_templates');
  my @dirs = ( $base );
  unshift @dirs, $local if $local;

  @dirs;
}

sub find_source {
  my ($class, $template, $cfg) = @_;

  my @dirs = $class->template_dirs($cfg);

  my $file = $cfg->entry('templates', $template) || $template;
  $file =~ /\.\w+$/ or $file .= ".tmpl";

  for my $dir (@dirs) {
    return "$dir/$file" if -f "$dir/$file";
  }

  return;
}

sub get_source {
  my ($class, $template, $cfg) = @_;

  my $path = $class->find_source($template, $cfg)
    or confess "Cannot find template $template";
  open SOURCE, "< $path"
    or confess "Cannot open template $path: $!";
  binmode SOURCE;
  my $html = do { local $/; <SOURCE> };
  close SOURCE;

  $html;
}

sub output_result {
  my ($class, $req, $result) = @_;

  select STDOUT;
  $| = 1;
  push @{$result->{headers}}, "Content-Type: $result->{type}"
    if $result->{type};
  push @{$result->{headers}}, $req->extra_headers;
  if (exists $ENV{GATEWAY_INTERFACE}
      && $ENV{GATEWAY_INTERFACE} =~ /^CGI-Perl\//) {
    require Apache;
    my $r = Apache->request or die;
    $r->send_cgi_header(join("\n", @{$result->{headers}})."\n\n");
  }
  else {
    print "$_\n" for @{$result->{headers}};
    print "\n";
  }
  print $result->{content};
}

1;
