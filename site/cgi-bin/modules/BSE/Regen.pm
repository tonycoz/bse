package BSE::Regen;
use strict;
use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(generate_article generate_all generate_button 
                regen_and_refresh generate_extras pregenerate_list generate_one_extra generate_base content_one_extra response_one_extra);
use Constants qw($GENERATE_BUTTON $SHOPID $AUTO_GENERATE);
use Carp qw(confess);
use BSE::WebUtil qw(refresh_to_admin);
use BSE::Util::HTML;

our $VERSION = "1.012";

# returns non-zero if the Regenerate button should work
sub generate_button {
  if ($GENERATE_BUTTON) {
    if (my $ref = ref $GENERATE_BUTTON) {
      if ($ref eq 'CODE') {
	return $GENERATE_BUTTON->();
      }
      else {
	# assumed to be an object
	return $GENERATE_BUTTON->want_button();
      }
    }
    else {
      return 1;
    }
  }
  return 0;
}

# regenerate an individual article
sub generate_low {
  my ($articles, $article, $cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my $outname;
  if ($article->is_dynamic) {
    my $debug_jit = $cfg->entry('debug', 'jit_dynamic_regen');
    $outname = $article->cached_filename($cfg);
    if ($article->{flags} !~ /R/ && 
	$cfg->entry('basic', 'jit_dynamic_pregen')) {
      $debug_jit and print STDERR "JIT: $article->{id} - deleting $outname\n";
      # just delete the file, page.pl will make it if needed
      unlink $outname;
      return;
    }
  }
  else {
    $outname = $article->link_to_filename($cfg)
      or return; # no output for this article 
  }

  if ($article->flags =~ /P/ && $article->{parentid} != -1) {
    # link to parent, remove the file
    unlink $outname;
    return;
  }

  unless ($article->should_generate) {
    # don't generate unlisted pages and remove any old content
    unlink $outname;
    return;
  }

  my $genname = $article->{generator};
  eval "use $genname";
  $@ && die $@;
  my $gen = $genname->new(articles=>$articles, cfg=>$cfg, top=>$article);

  my $content = $gen->generate($article, $articles);
  my $tempname = $outname . ".work";
  unlink $tempname;
  _write_text($tempname, $content, $cfg);
  unlink $outname;
  rename($tempname, $outname)
    or die "Cannot rename $tempname to $outname: $!";
}

sub generate_article {
  my ($articles, $article, $cfg) = @_;

  while ($article) {
    generate_low($articles, $article, $cfg) 
      if $article->{link} && $article->{template};

    if ($article->{parentid} != -1) {
      $article = $articles->getByPkey($article->{parentid});
    }
    else {
      undef $article;
    }
  }
}

sub _cfg_presets {
  my ($cfg, $article, $type) = @_;

  my $section = "$type settings";

  require Articles;
  for my $field (Article->columns) {
    if ($cfg->entry($section, $field)) {
      $article->{$field} = $cfg->entryVar($section, $field);
    }
  }
}

sub _search_presets {
  my ($cfg) = @_;

  # build a dummy article
  use Constants qw($SEARCH_TITLE $SEARCH_TITLE_IMAGE $CGI_URI);
  require Articles;
  my %article = map { $_, '' } Article->columns;
  @article{qw(id parentid title titleImage displayOrder link level listed force_dynamic)} =
    (-4, -1, $SEARCH_TITLE, $SEARCH_TITLE_IMAGE, 0, $CGI_URI."/search.pl", 0, 1, 1);

  $article{link} = $cfg->entryErr('site', 'url') . $article{link};

  _cfg_presets($cfg, \%article, "search");

  return _dummy_article(\%article);
}

sub _shop_presets {
  my ($cfg) = @_;

  require Articles;
  my $shop_base = Articles->getByPkey($SHOPID);
  my $shop = { map { $_ => $shop_base->{$_} } $shop_base->columns };
  $shop->{link} =~ /^\w+:/
    or $shop->{link} = $cfg->entryErr('site', 'url') . $shop->{link};
  $shop->{id} = -3; # some random negative number

  _cfg_presets($cfg, $shop, "shop");

  return _dummy_article($shop);
}

sub _extras_presets {
  my ($cfg, $presets) = @_;

  require Articles;
  my %article = map { $_, '' } Article->columns;
  $article{displayOrder} = 1;
  $article{id} = -5;
  $article{parentid} = -1;
  $article{link} = $cfg->entryErr('site', 'url');
  _cfg_presets($cfg, \%article, $presets);

  return _dummy_article(\%article);
}

my %builtin_extras =
  (
   search => [ "search" ],
   shop =>
   [
    'cart', 'checkoutnew', 'checkoutfinal',
    'checkoutpay',
   ],
  );

my %abs_urls =
  (
   shop => 1,
   search => 0,
  );

my %builtin_lookup;

{
  for my $type (keys %builtin_extras) {
    for my $name (@{$builtin_extras{$type}}) {
      $builtin_lookup{$name} = $type;
    }
  }
}

sub _extras_cfg {
  my ($cfg, $extra) = @_;

  my %result;
  if ($builtin_extras{$extra->{set}}) {
    $result{abs_urls} = $abs_urls{$extra->{set}};
  }
  else {
    $result{abs_urls} = $cfg->entry("$extra->{type} settings", "abs_urls", 0);
  }

  return \%result;
}

sub pregenerate_list {
  my ($cfg) = @_;

  my $template_dir = $cfg->entryVar('paths', 'templates');

  # this will change to a directory that can be safely blown away
  my $pregen_path = $template_dir;

  my @result =
    (
     (
      map
      +{
	name => "$_.tmpl",
	base => $_ . "_base.tmpl",
	type => $builtin_lookup{$_},
	set => $builtin_lookup{$_},
	sort => 0,
	outpath => $pregen_path,
	abs_urls => $abs_urls{$builtin_lookup{$_}},
	dynamic => 1,
       }, keys %builtin_lookup
     ),
    );

  # cfg pregen
  my %pregen = $cfg->entries('pregenerate');
  for my $out (keys %pregen) {
    my ($type, $input) = split ',', $pregen{$out}, 2;
    push @result,
      +{
	name => $out,
	base => $input,
	type => $type,
	set => "pregen",
	sort => 1,
	outpath => $pregen_path,
	dynamic => 1,
       };
  }

  # extras file
  if (open my $extras, "$template_dir/extras.txt") {
    while (<$extras>) {
      chomp;
      next if /^\s*#/;
      if (/^(\S+)\s+(\S+)/) {
	push @result,
	  {
	   name => $2,
	   base => $1,
	   type => "extras",
	   set => "extras",
	   sort => 2,
	   outpath => $cfg->content_base_path,
	   dynamic => 0,
	  };
      }
    }
    close $extras;
  }

  return sort {
    $a->{sort} <=> $b->{sort}
      || $a->{set} cmp $b->{set}
	|| $a->{type} cmp $b->{type}
	  || lc $a->{name} cmp lc $b->{name}
    } @result;
}

sub _make_extra_art {
  my ($cfg, $extra) = @_;

  if ($extra->{set} eq "shop") {
    return _shop_presets($cfg);
  }
  elsif ($extra->{set} eq "search") {
    return _search_presets($cfg);
  }
  elsif ($extra->{set} eq "pregen"
	 || $extra->{set} eq "extras") {
    return _extras_presets($cfg, $extra->{type});
  }
  else {
    confess "Unknown extras set $extra->{set}";
  }
}

sub _make_extra_gen {
  my ($cfg, $extra) = @_;

  my $article = _make_extra_art($cfg, $extra);
  require Generate::Article;
  my %opts =
    (
     cfg => $cfg,
     top => $article,
    );
  if ($extra->{dynamic}) {
    $opts{force_dynamic} = 1;
  }
  require Generate::Article;
  my $gen = Generate::Article->new(%opts);

  return ($article, $gen);
}

sub _common_one_extra {
  my ($articles, $extra, $cfg) = @_;

  my ($article, $gen) = _make_extra_gen($cfg, $extra);
  my %acts;
  %acts = $gen->baseActs($articles, \%acts, $article);
  if (_extras_cfg($cfg, $extra)->{abs_urls}) {
    my $oldurl = $acts{url};
    $acts{url} =
      sub {
        my $value = $oldurl->(@_);
	$value =~ /^<:/ and return $value;
        unless ($value =~ /^\w+:/) {
          # put in the base site url
          $value = $cfg->entryErr('site', 'url').$value;
        }
        return $value;
      };
  }

  my $content = BSE::Template->get_page($extra->{base}, $cfg, \%acts,
					undef, undef, $gen->variables);

  return wantarray ? ( $content, $article ) : $content;
}

sub response_one_extra {
  my ($articles, $extra) = @_;

  my $cfg = BSE::Cfg->single;
  my $content = _common_one_extra($articles, $extra, $cfg);

  return BSE::Template->make_response($content, BSE::Template->get_type($cfg, $extra->{template}));
}

sub content_one_extra {
  my ($articles, $extra) = @_;

  my $cfg = BSE::Cfg->single;
  return _common_one_extra($articles, $extra, $cfg);
}

sub generate_one_extra {
  my ($articles, $extra) = @_;

  my $cfg = BSE::Cfg->single;
  my $content = _common_one_extra($articles, $extra, $cfg);
  my $outname = $extra->{outpath} . "/". $extra->{name};
  my $workname = $outname . ".work";
  _write_text($workname, $content, $cfg);
  unlink $outname;
  rename $workname, $outname
    or die "Cannot rename $workname to $outname: $!";
}

sub generate_base {
  my %opts = @_;

  my $cfg = delete $opts{cfg} || BSE::Cfg->single;

  my $articles = delete $opts{articles} || "Articles";
  my $extras = delete $opts{extras} || [ pregenerate_list($cfg) ];

  my $progress = delete $opts{progress} || sub {};

  my @extras = sort
    {
      $a->{sort} <=> $b->{sort}
	|| $a->{type} cmp $b->{type}
	  || lc $a->{name} cmp lc $b->{name}
    } @$extras;

  my $count = @extras;
  $progress->({ type => "extras", count => $count, info => "count" }, "$count base pages");
  my $set = "";
  my $type = "";
  my ($gen, $article);
  my %acts;
  for my $extra (@extras) {
    if ($extra->{set} ne $set || $extra->{type} ne $type) {
      ($article, $gen) = _make_extra_gen($cfg, $extra);
      %acts = $gen->baseActs($articles, \%acts, $article);
      if (_extras_cfg($cfg, $extra)->{abs_urls}) {
	my $oldurl = $acts{url};
	$acts{url} =
	  sub {
	    my $value = $oldurl->(@_);
	    $value =~ /^<:/ and return $value;
	    unless ($value =~ /^\w+:/) {
	      # put in the base site url
	      $value = $cfg->entryErr('site', 'url').$value;
	    }
	    return $value;
	  };
      }
      $progress->($extra, "Generating $extra->{name}");
      my $content = BSE::Template->get_page($extra->{base}, $cfg, \%acts,
					    undef, undef, $gen->variables);
      my $outname = $extra->{outpath} . "/". $extra->{name};
      my $workname = $outname . ".work";
      _write_text($workname, $content, $cfg);
      unlink $outname;
      rename $workname, $outname
	or die "Cannot rename $workname to $outname: $!";
    }
  }
}

sub generate_all {
  my ($articles, $cfg, $callback) = @_;

  my @articleids = $articles->allids;
  my $pc = 0;
  $callback->("Generating articles (".scalar(@articleids)." to do)")
    if $callback;
  my $index;
  my $total = 0;
  Squirrel::Table->caching(1);
  my $allstart = time;
  for my $articleid (@articleids) {
    my $article = $articles->getByPkey($articleid);
    ++$index;
    my $newpc = $index / @articleids * 100;
    my $now = time;
    if ($callback && $newpc >= $pc + 1 || abs($newpc-100) < 0.01) {
      $callback->(sprintf("%5d:  %.1f%% done - elapsed: %.1f", $articleid, $newpc, $now - $allstart)) if $callback;
      $pc = int $newpc;
    }
    if ($article->{link} && $article->{template}) {
      #$callback->("Article $articleid");
      generate_low($articles, $article, $cfg);
    }
  }

  my $last_section = "";
  my $progress = $callback ? sub {
    my $data = shift;
    if (!$data->{count} && $data->{set} ne $last_section) {
      $callback->("Regenerating $data->{set} pages");
      $last_section = $data->{set};
    }
    $callback->("  @_")
  } : undef;
  generate_base(cfg => $cfg, articles => $articles, progress => $progress);

  $callback->("Total of ".(time()-$allstart)." seconds") if $callback;
}

sub _write_text {
  my ($filename, $data, $cfg) = @_;

  open my $fh, ">", $filename
    or die "Cannot create $filename: $!";
  if ($cfg->utf8) {
    my $charset = $cfg->charset;
    binmode $fh,  ":encoding($charset)";
  }
  print $fh $data
    or die "Cannot write $filename: $!";
  close $fh
    or die "Cannot close $filename: $!";
}

sub _dummy_article {
  my ($data) = @_;

  return bless $data, "BSE::Regen::DummyArticle";
}

package BSE::Regen::DummyArticle;
use base 'BSE::TB::SiteCommon';

sub images {
  return;
}

sub files {
  return;
}

{
  use Articles;
  for my $name (Article->columns) {
    eval "sub $name { \$_[0]{$name} }";
  }
}

sub restricted_method {
  return 0;
}

sub section {
  $_[0];
}

sub is_descendant_of {
  0;
}

sub parent {
  return;
}

sub is_dynamic {
  1;
}

sub is_step_ancestor {
  0;
}

1;
