package Util;
use strict;
use vars qw(@ISA @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(generate_article generate_all generate_button 
                refresh_to regen_and_refresh);
use Constants qw($CONTENTBASE $TMPLDIR $URLBASE %TEMPLATE_OPTS
		 $GENERATE_BUTTON $SHOPID $AUTO_GENERATE);

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
  unlink $outname;
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

  require 'Generate/Article.pm';
  my $gen = Generate::Article->new;

  # build a dummy article
  use Constants qw($SEARCH_TITLE $SEARCH_TITLE_IMAGE $CGI_URI);
  my %article = map { $_, '' } Article->columns;
  @article{qw(id parentid title titleImage displayOrder link level listed)} =
    (-1, -1, $SEARCH_TITLE, $SEARCH_TITLE_IMAGE, 0, $CGI_URI."/search.pl", 0, 1);

  my %acts;
  %acts = $gen->baseActs($articles, \%acts, \%article);
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
     'cart', 'checkout', 'checkoutfinal', 'checkoutcard', 'checkoutconfirm',
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
    unlink $finalname;
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
    unlink $finalname;
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

sub refresh_to {
  my ($where) = @_;

  print "Content-Type: text/html\n";
  print qq!Refresh: 0; url="$where"\n\n<html></html>\n!;
}

=item regen_and_refresh($articles, $article, $generate, $refreshto)

An error checking wrapper around the page regeneration code.

In some cases IIS appears to lock the static pages, which was causing
various problems.  Here we catch the error and let the user know what
is going on.

If $article is set to undef then everything is regenerated.

$generate is typically 1 or $AUTO_GENERATE

Returns 1 if the regeneration was performed successfully.

=cut

sub regen_and_refresh {
  my ($articles, $article, $generate, $refreshto) = @_;

  if ($generate) {
    eval {
      if ($article) {
	generate_article($articles, $article);
      }
      else {
	generate_all($articles);
      }
    };
    if ($@) {
      my $error = $@;
      my %acts;
      %acts =
	(
	 ifArticle => sub { $article },
	 article => sub { CGI::escapeHTML($article->{$_[0]}) },
	 error => sub { CGI::escapeHTML($error) },
	);
      my $gen = Squirrel::Template->new();
      print "Content-Type: text/html\n\n";
      print $gen->show_page($TMPLDIR, 'admin/regenerror.tmpl', \%acts);
      
      return 0;
    }
  }

  refresh_to($refreshto);

  return 1;
}

1;
