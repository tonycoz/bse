package Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(generate_article generate_all generate_button);
use Constants qw($CONTENTBASE $TMPLDIR $URLBASE %TEMPLATE_OPTS
		 $GENERATE_BUTTON $SHOPID);

my %gen_cache;

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
  my ($articles, $article) = @_;

  my $genname = $article->{generator};

  eval "use $genname";
  $@ && die $@;
  $gen_cache{$genname} ||= $genname->new(articles=>$articles);

  my $outname = $article->{link};
  $outname =~ s!/\w*$!!;
  $outname =~ s{^\w+://[\w.-]+}{};
  $outname = $CONTENTBASE . $outname;
  $outname =~ s!//+!/!;
  my $content = $gen_cache{$genname}->generate($article, $articles);
  my $tempname = $outname . ".work";
  unlink $tempname;
  open OUT, "> $tempname" or die "Cannot create $tempname: $!";
  print OUT $content or die "Cannot write content to $outname: $!";
  close OUT or die "Cannot close $outname: $!";
  rename($tempname, $outname)
    or die "Cannot rename $tempname to $outname: $!";
}

sub generate_article {
  my ($articles, $article) = @_;

  while ($article) {
    generate_low($articles, $article) 
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
  my ($articles) = @_;
  use Generate;
  my $gen = Generate->new;
  my %acts;
  %acts = $gen->baseActs($articles, \%acts);
  my $templ = Squirrel::Template->new(%TEMPLATE_OPTS);
  my $content = $templ->show_page($TMPLDIR, 'search_base.tmpl', \%acts);
  my $outname = "$TMPLDIR/search.tmpl.work";
  my $finalname = "$TMPLDIR/search.tmpl";
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
     'cart', 'checkout', 'checkoutfinal',
    );
  require 'Generate/Article.pm';
  my $shop = $articles->getByPkey($SHOPID);
  my $gen = Generate::Article->new;
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
          $value = $URLBASE.$value;
        }
        return $value;
      };
    my $templ = Squirrel::Template->new(%TEMPLATE_OPTS);
    my $content = $templ->show_page($TMPLDIR, "${name}_base.tmpl", \%acts);
    my $outname = "$TMPLDIR/$name.tmpl.work";
    my $finalname = "$TMPLDIR/$name.tmpl";
    open OUT, "> $outname"
      or die "Cannot open $outname for write: $!";
    print OUT $content
      or die "Cannot write to $outname: $!";
    close OUT
      or die "Cannot close $outname: $!";
    rename $outname, $finalname
      or die "Cannot rename $outname to $finalname: $!";
  }
}

sub generate_extras {
  my ($articles) = @_;

  open EXTRAS, "$TMPLDIR/extras.txt"
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
  my $gen = Generate->new;
  for my $row (@extras) {
    my ($in, $out) = @$row;
    my %acts;
    %acts = $gen->baseActs($articles, \%acts);
    my $templ = Squirrel::Template->new(%TEMPLATE_OPTS);
    my $content = $templ->show_page($TMPLDIR, $in, \%acts);
    my $outname = $CONTENTBASE . $out . ".work";
    my $finalname = $CONTENTBASE . $out;
    open OUT, "> $outname"
      or die "Cannot open $outname for write: $!";
    print OUT $content
      or die "Cannot write content to $outname: $!";
    close OUT 
      or die "Cannot close $outname: $!";
    rename $outname, $finalname
      or die "Cannot rename $outname to $finalname: $!";
  }
}

sub generate_all {
  my ($articles) = @_;

  %gen_cache = ();
  for my $article ($articles->all()) {
    generate_low($articles, $article) 
      if $article->{link} && $article->{template};
  }
  %gen_cache = ();

  generate_search($articles);

  generate_shop($articles);

  generate_extras($articles);
}

1;
