package Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(generate_article generate_all generate_button 
                regen_and_refresh);
use Constants qw($CONTENTBASE $GENERATE_BUTTON $SHOPID $AUTO_GENERATE);
use Carp qw(confess);
use BSE::WebUtil qw(refresh_to_admin);

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

  $cfg ||= BSE::Cfg->new;

  my $outname;
  if ($article->is_dynamic) {
    my $debug_jit = $cfg->entry('debug', 'jit_dynamic_regen');
    my $dynamic_path = $cfg->entryVar('paths', 'dynamic_cache');
    $outname = $dynamic_path . "/" . $article->{id} . ".html";
    if ($article->{flags} !~ /R/ && 
	$cfg->entry('basic', 'jit_dynamic_pregen')) {
      $debug_jit and print STDERR "JIT: $article->{id} - deleting $outname\n";
      # just delete the file, page.pl will make it if needed
      unlink $outname;
      return;
    }
  }
  else {
    $outname = $article->{link};
    $outname =~ s!/\w*$!!;
    $outname =~ s{^\w+://[\w.-]+(?::\d+)?}{};
    $outname = $CONTENTBASE . $outname;
    $outname =~ s!//+!/!;
  }

  my $genname = $article->{generator};
  eval "use $genname";
  $@ && die $@;
  my $gen = $genname->new(articles=>$articles, cfg=>$cfg, top=>$article);

  my $content = $gen->generate($article, $articles);
  my $tempname = $outname . ".work";
  unlink $tempname;
  open OUT, "> $tempname" or die "Cannot create $tempname: $!";
  print OUT $content or die "Cannot write content to $outname: $!";
  close OUT or die "Cannot close $outname: $!";
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

# generates search.tmpl from search_base.tmpl
sub generate_search {
  my ($articles, $cfg) = @_;

  $cfg or confess "Call generate search with a config object";

  # build a dummy article
  use Constants qw($SEARCH_TITLE $SEARCH_TITLE_IMAGE $CGI_URI);
  my %article = map { $_, '' } Article->columns;
  @article{qw(id parentid title titleImage displayOrder link level listed)} =
    (-1, -1, $SEARCH_TITLE, $SEARCH_TITLE_IMAGE, 0, $CGI_URI."/search.pl", 0, 1);

  require 'Generate/Article.pm';
  my $gen = Generate::Article->new(cfg=>$cfg, top => \%article, 
				   force_dynamic => 1);

  my %acts;
  %acts = $gen->baseActs($articles, \%acts, \%article);
  my $content = BSE::Template->get_page('search_base', $cfg, \%acts);
  my $tmpldir = $cfg->entryVar('paths', 'templates');
  my $outname = "$tmpldir/search.tmpl.work";
  my $finalname = "$tmpldir/search.tmpl";
  open OUT, "> $outname"
    or die "Cannot open $outname for write: $!";
  print OUT $content
    or die "Cannot write to $outname: $!";
  close OUT
    or die "Cannot close $outname: $!";
  rename $outname, $finalname
    or die "Cannot rename $outname to $finalname: $!";
}

sub generate_shop {
  my ($articles) = @_;
  my @pages =
    (
     'cart', 'checkoutnew', 'checkoutfinal', 'checkoutcard', 'checkoutconfirm',
     'checkoutpay',
    );
  require 'Generate/Article.pm';
  my $shop = $articles->getByPkey($SHOPID);
  my $cfg = BSE::Cfg->new;
  my $gen = Generate::Article->new(cfg=>$cfg, top=>$shop, force_dynamic => 1);
  for my $name (@pages) {
    my %acts;
    %acts = $gen->baseActs($articles, \%acts, $shop);
    # different url behaviour - point the user at the http version
    # of the site if the url contains no scheme
    my $oldurl = $acts{url};
    $acts{url} =
      sub {
        my $value = $oldurl->(@_);
        unless ($value =~ /^\w+:/) {
          # put in the base site url
          $value = $cfg->entryErr('site', 'url').$value;
        }
        return $value;
      };
    my $content = BSE::Template->get_page("${name}_base", $cfg, \%acts);
    my $tmpldir = $cfg->entryVar('paths', 'templates');
    my $outname = "$tmpldir/$name.tmpl.work";
    my $finalname = "$tmpldir/$name.tmpl";
    open OUT, "> $outname"
      or die "Cannot open $outname for write: $!";
    print OUT $content
      or die "Cannot write to $outname: $!";
    close OUT
      or die "Cannot close $outname: $!";
    unlink $finalname;
    rename $outname, $finalname
      or die "Cannot rename $outname to $finalname: $!";
  }
}

sub generate_extras {
  my ($articles, $cfg, $callback) = @_;

  use BSE::Cfg;
  $cfg ||= BSE::Cfg->new;
  my $template_dir = $cfg->entryVar('paths', 'templates');

  open EXTRAS, "$template_dir/extras.txt"
    or return;
  my @extras;
  while (<EXTRAS>) {
    chomp;
    next if /^\s*#/;
    if (/^(\S+)\s+(\S+)/) {
      push(@extras, [ $1, $2 ]);
    }
  }
  close EXTRAS;
  use Generate;
  require BSE::Template;
  my $gen = Generate->new(cfg=>$cfg);
  for my $row (@extras) {
    my ($in, $out) = @$row;
    $callback->("$in to $out") if $callback;
    my %acts;
    %acts = $gen->baseActs($articles, \%acts);
    my $oldurl = $acts{url};
    $acts{url} =
      sub {
	my $value = $oldurl->(@_);
	unless ($value =~ /^\w+:/) {
	  # put in the base site url
	  $value = $cfg->entryErr('site', 'url').$value;
	}
	return $value;
      };
    my $content = BSE::Template->get_page($in, $cfg, \%acts);
    my $outname = $CONTENTBASE . $out . ".work";
    my $finalname = $CONTENTBASE . $out;
    open OUT, "> $outname"
      or die "Cannot open $outname for write: $!";
    print OUT $content
      or die "Cannot write content to $outname: $!";
    close OUT 
      or die "Cannot close $outname: $!";
    unlink $finalname;
    rename $outname, $finalname
      or die "Cannot rename $outname to $finalname: $!";
  }

  # more extras
  my %entries = $cfg->entries('pregenerate');
  if (keys %entries) {
    require 'Generate/Article.pm';
    for my $out (keys %entries) {
      my ($presets, $input) = split ',', $entries{$out}, 2;
      $callback->("$input to $out with $presets") if $callback;
      my %article = map { $_, '' } Article->columns;
      $article{displayOrder} = 1;
      $article{id} = -5;
      $article{parentid} = -1;
      $article{link} = $cfg->entryErr('site', 'url');
      for my $field (Article->columns) {
	if ($cfg->entry("$presets settings", $field)) {
	  $article{$field} = $cfg->entryVar("$presets settings", $field);
	}
      }
      # by default all of these are handled as dynamic, but it can be 
      # overidden, eg. the error template
      my $dynamic = $cfg->entry("$presets settings", 'dynamic', 1);
      my %acts;
      my $gen = Generate::Article->new(cfg=>$cfg, top=>\%article, 
				       force_dynamic => $dynamic);
      %acts = $gen->baseActs($articles, \%acts, \%article);
      my $oldurl = $acts{url};
      $acts{url} =
	sub {
	  my $value = $oldurl->(@_);
	  unless ($value =~ /^\w+:/) {
	    # put in the base site url
	    $value = $cfg->entryErr('site', 'url').$value;
	  }
	  return $value;
	};
      my $content = BSE::Template->get_page($input, $cfg, \%acts);
      my $outname = $template_dir .'/'.$out.'.work';
      my $finalname = $template_dir . '/'. $out;
      open OUT, "> $outname"
	or die "Cannot open $outname for write: $!";
      print OUT $content
	or die "Cannot write content to $outname: $!";
      close OUT
	or die "Cannot close $outname: $!";
      unlink $finalname;
      rename $outname, $finalname
	or die "Cannot rename $outname to $finalname: $!";
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
    if ($article->{link} && $article->{template}) {
      #$callback->("Article $articleid");
      generate_low($articles, $article, $cfg);
    }
    my $newpc = $index / @articleids * 100;
    my $now = time;
    if ($callback && $newpc >= $pc + 1 || abs($newpc-100) < 0.01) {
      $callback->(sprintf("%5d:  %.1f%% done - elapsed: %.1f", $articleid, $newpc, $now - $allstart)) if $callback;
      $pc = int $newpc;
    }
  }

  $callback->("Generating search base") if $callback;
  generate_search($articles, $cfg);

  $callback->("Generating shop base pages") if $callback;
  generate_shop($articles);

  $callback->("Generating extra pages") if $callback;
  generate_extras($articles, $cfg, $callback);

  $callback->("Total of ".(time()-$allstart)." seconds") if $callback;
}

=item regen_and_refresh($articles, $article, $generate, $refreshto, $cfg, $progress)

An error checking wrapper around the page regeneration code.

In some cases IIS appears to lock the static pages, which was causing
various problems.  Here we catch the error and let the user know what
is going on.

If $article is set to undef then everything is regenerated.

$cfg should be an initialized BSE::Cfg object

$progress should be either missing, undef or a code reference.

$generate is typically 1 or $AUTO_GENERATE

Returns 1 if the regeneration was performed successfully.

=cut

sub regen_and_refresh {
  my ($articles, $article, $generate, $refreshto, $cfg, $progress) = @_;

  if ($generate) {
    eval {
      if ($article) {
	if ($article eq 'extras') {
	  $progress->("Generating search base") if $progress;
	  generate_search($articles, $cfg);
	  
	  $progress->("Generating shop base pages") if $progress  ;
	  generate_shop($articles);
	  
	  $progress->("Generating extra pages") if $progress;
	  generate_extras($articles, $cfg, $progress);
	}
	else {
	  generate_article($articles, $article, $cfg);
	}
      }
      else {
	generate_all($articles, $cfg, $progress);
      }
    };
    if ($@) {
      if ($progress) {
	$progress->($@);
      }
      else {
	my $error = $@;
	require 'BSE/Util/Tags.pm';
	require 'BSE/Template.pm';
	my %acts;
	%acts =
	  (
	   BSE::Util::Tags->basic(\%acts, undef, $cfg),
	   ifArticle => sub { $article },
	   article => 
	   sub { 
	     if (ref $article) {
	       return CGI::escapeHTML($article->{$_[0]});
	     }
	     else {
	       return 'extras';
	     }
	   },
	   error => sub { CGI::escapeHTML($error) },
	  );
	BSE::Template->show_page('admin/regenerror', $cfg, \%acts);
	
	return 0;
      }
    }
  }

  unless ($progress) {
    refresh_to_admin($cfg, $refreshto);
  }

  return 1;
}

1;
