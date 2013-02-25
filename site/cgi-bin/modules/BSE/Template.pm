package BSE::Template;
use strict;
use Squirrel::Template;
use Carp qw(confess cluck);
use Config ();

our $VERSION = "1.010";

my %formats =
  (
   html => sub {
     require BSE::Util::HTML;
     return BSE::Util::HTML::escape_html($_[0]);
   },
   uri => sub {
     require BSE::Util::HTML;
     return BSE::Util::HTML::escape_uri($_[0]);
   },
   raw => sub {
     return $_[0];
   },
  );
$formats{h} = $formats{html};
$formats{u} = $formats{uri};

sub templater {
  my ($class, $cfg, $rsets) = @_;

  my @conf_dirs = $class->template_dirs($cfg);
  my @dirs;
  if ($rsets && @$rsets) {
    for my $set (@$rsets) {
      push @dirs, map "$_/$set", @conf_dirs;
    }
    push @dirs, @conf_dirs;
  }
  else {
    @dirs = @conf_dirs;
  }

  my %opts =
    (
     template_dir => \@dirs,
     utf8 => $cfg->utf8,
     charset => $cfg->charset,
     formats => \%formats,
     def_format => $cfg->entry("html", "tagformat", "html"),
     trace_noimpl => scalar($cfg->entry("debug", "trace_noimpl", 0)),
    );
  if ($cfg->entry("basic", "cache_templates")) {
    require BSE::Cache;
    $opts{cache} = BSE::Cache->load($cfg);
  }
  if ($cfg->entry("basic", "cache_templates_locally")) {
    $opts{cache_locally} = 1;
  }

  $opts{preload} = $cfg->entry("basic", "preload_template");

  return Squirrel::Template->new(%opts);
}

sub _get_filename {
  my ($class, $cfg, $template) = @_;

  my $file = $cfg->entry('templates', $template) || $template;
  $file =~ /\.\w+$/ or $file .= ".tmpl";

  return $file;
}

sub get_page {
  my ($class, $template, $cfg, $acts, $base_template, $rsets, $vars) = @_;

  my $file = $class->_get_filename($cfg, $template);
  my $obj = $class->templater($cfg, $rsets);

  my $out;
  if ($base_template) {
    unless ($class->find_source($template, $cfg)) {
      $template = $base_template;
      $file = $class->_get_filename($cfg, $template);
    }
  }

  return $obj->show_page(undef, $file, $acts, undef, undef, $vars);
}

sub replace {
  my ($class, $source, $cfg, $acts, $vars) = @_;

  my $obj = $class->templater($cfg);

  $obj->replace_template($source, $acts, undef, undef, $vars);
}

sub charset {
  my ($class, $cfg) = @_;

  return $cfg->charset;
}

sub utf8 {
  my ($class, $cfg) = @_;

  return $cfg->utf8;
}

sub html_type {
  my ($class, $cfg) = @_;

  my $type = "text/html";
  my $charset = $class->charset($cfg);
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
  my ($class, $template, $cfg, $acts, $base_template, $rsets, $vars) = @_;

  my $content = $class->get_page($template, $cfg, $acts,
				 $base_template, $rsets, $vars);

  return $class->make_response($content, $class->get_type($cfg, $template));
}

sub make_response {
  my ($class, $content, $type) = @_;

  if ($type =~ /\bcharset=([\w-]+)/) {
    my $charset = $1;

    require Encode;
    Encode->import();
    my $cfg = BSE::Cfg->single;
    my $check = $cfg->entry("utf8", "check", Encode::FB_DEFAULT());
    $check = oct($check) if $check =~ /^0/;

    $content = Encode::encode($charset, $content, $check);
  }

  my $result =
    {
     type => $type,
     content => $content,
    };
  push @{$result->{headers}}, "Content-Length: ".length($result->{content});

  return $result;
}

sub get_refresh {
  my ($class, $url, $cfg) = @_;

  return
    {
     content => '',
     headers => [ 
		 "Location: $url",
		 "Status: 303"
		],
    };
}

sub get_moved {
  my ($class, $url, $cfg) = @_;

  return
    {
     content => '',
     headers => [ 
		 "Location: $url",
		 "Status: 301"
		],
    };
}

sub template_dirs {
  my ($class, $cfg) = @_;

  ref($cfg) eq 'BSE::Cfg'
    or confess "Invalid cfg $cfg supplied\n";

  my $path_sep = $Config::Config{path_sep};

  my $base = $cfg->entryVar('paths', 'templates');
  my @dirs = split /\Q$path_sep/, $base;
  my $local = $cfg->entry('paths', 'local_templates');
  if ($local) {
    unshift @dirs, split /\Q$path_sep/,
      $cfg->entryVar('paths', 'local_templates');
  }

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
  open my $source, "< $path"
    or confess "Cannot open template $path: $!";
  binmode $source;
  if ($cfg->utf8) {
    my $charset = $cfg->charset;
    binmode $source, ":encoding($charset)";
  }
  my $html = do { local $/; <$source> };
  close $source;

  $html;
}

sub output_result {
  my ($class, $req, $result) = @_;

  $class->output_resultc($req->cfg, $result);
}

sub output_resultc {
  my ($class, $cfg, $result) = @_;

  $result 
    or return;

  select STDOUT;
  $| = 1;
  push @{$result->{headers}}, "Content-Type: $result->{type}"
    if $result->{type};
  my $add_cache_control = $cfg->entry('basic', 'no_cache_dynamic', 1);
  if (defined $result->{no_cache_dynamic}) {
    $add_cache_control = $result->{no_cache_dynamic};
  }
  if ($add_cache_control) {
    for my $header (@{$result->{headers}}) {
      if ($header =~ /^cache-control:/i) {
	$add_cache_control = 0;
	last;
      }
    }
    if ($add_cache_control) {
      push @{$result->{headers}}, "Cache-Control: no-cache";
    }
  }

  if ($result->{content_filename}) {
    # at some point, if we have a FEP like perlbal of nginx we might
    # get it to serve the file instead
    if (open my $fh, "<", $result->{content_filename}) {
      binmode $fh;
      $result->{content_fh} = $fh;
    }
    else {
      print STDERR "$ENV{SCRIPT_NAME}: ** cannot open file $result->{content_filename}: $!\n";
      $result->{content} = "* Internal error";
    }
  }

  if (!grep /^content-length:/i, @{$result->{headers}}) {
    my $length;
    if (defined $result->{content}) {
      $length = length $result->{content};
    }
    if (defined $result->{content_fh}) {
      # this may need to change if we support byte ranges
      $length += -s $result->{content_fh};
    }

    if (defined $length) {
      push @{$result->{headers}}, "Content-Length: $length";
    }
  }
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
  if (defined $result->{content}) {
    if ($result->{content} =~ /([^\x00-\xff])/) {
      cluck "Wide character in content (\\x{", sprintf("%X", ord $1), "})";
    }
    print $result->{content};
  }
  elsif ($result->{content_fh}) {
    # in the future this could be updated to support byte ranges
    local $/ = \16384;
    my $fh = $result->{content_fh};
    binmode $fh;
    while (my $data = <$fh>) {
      print $data;
    }
  }
  else {
    print STDERR "$ENV{SCRIPT_NAME}: ** No content supplied\n";
    print "** Internal error\n";
  }

  if ($result->{content}
      && $result->{type} =~ m(text/html|application/xhtml\+xml)
      && $cfg->entry("html", "validate", 0)) {
    require BSE::Util::ValidateHTML;
    BSE::Util::ValidateHTML->validate($cfg, $result);
  }
}

1;
