#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use Constants qw($BASEDIR $MAXPHRASE $DATADIR @SEARCH_EXCLUDE @SEARCH_INCLUDE $SEARCH_LEVEL);
use BSE::DB;
use Generate;
use BSE::Cfg;
use BSE::WebUtil 'refresh_to_admin';
use Time::HiRes qw(time);
my $in_cgi = exists $ENV{REQUEST_METHOD};
my $verbose;
my $start = time();

my $cfg;
$| = 1;
if ($in_cgi) {
  # make sure the user can do this
  require BSE::Request;
  my $req = BSE::Request->new;
  $cfg = $req->cfg;
  if (!$req->check_admin_logon) {
    my $url = $req->url("logon", { m => "You must logon to dump the database" });
    $req->output_result($req->get_refresh($url));
    exit;
  }
  elsif (!$req->user_can("bse_makeindex")) {
    my $url = $req->url("menu", { m => "You don't have access to build the search index" });
    $req->output_result($req->get_refresh($url));
    exit;
  }

  $verbose = $req->cgi->param("verbose") || 0;
  print "Content-Type: text/plain\n\n" if $verbose;
  #eval "use CGI::Carp qw(fatalsToBrowser)";
}
else {
  require Getopt::Long;
  Getopt::Long->import;
  GetOptions("v:i" => \$verbose);
  if (defined $verbose && !$verbose) {
    $verbose = 1;
  }

  $cfg = BSE::Cfg->new;
  BSE::DB->init($cfg);
}

my $urlbase = $cfg->entryVar('site', 'url');

my $articles = 'Articles';

# scores depending on where the term appears
# these may need some tuning
# preferably, keep these to single digits
my %scores =
  (
   title=>5,
   body=>3,
   keyword=>4,
   pageTitle=>5,
   author=>4,
   file_displayName => 2,
   file_description=>2,
   file_notes => 1,
   summary => 0,
   description => 0,
   product_code => 0,
  );

for my $name (keys %scores) {
  my $score = $cfg->entry('search index scores', $name);
  if (defined($score) && $score =~ /^\d+$/) {
    $scores{$name} = $score;
  }
}

# if the level of the article is higher than this, store it's parentid 
# instead
my $max_level = $SEARCH_LEVEL;

my $indexer_class = $cfg->entry('search', 'indexer', 'BSE::Index::BSE');
(my $indexer_file = $indexer_class . ".pm") =~ s!::!/!g;
require $indexer_file;
# key is phrase, value is hashref with $id -> $sectionid
my $indexer = $indexer_class->new
  (
   cfg => $cfg,
   scores => \%scores,
   verbose => $verbose,
  );

eval {
  vnote($start, $verbose, "s1::Starting index");
  $indexer->start_index();
  vnote($start, $verbose, "s2::Starting article scan");
  makeIndex($articles, $start, $verbose);
  vnote($start, $verbose, "f2::Populating search index");
  $indexer->end_index();
  vnote($start, $verbose, "f1::Indexing complete");
};
if ($@) {
  print STDERR "Indexing error: $@\n";
}

if ($in_cgi && !$verbose) {
  refresh_to_admin($cfg, "/cgi-bin/admin/menu.pl");
}

sub makeIndex {
  my ($articles, $start, $verbose) = @_;
  my %dont_search;
  my %do_search;
  @dont_search{@SEARCH_EXCLUDE} = @SEARCH_EXCLUDE;
  @do_search{@SEARCH_INCLUDE} = @SEARCH_INCLUDE;
  vnote($start, $verbose, "s::Loading article ids");
  my @ids = $articles->allids;
  my $count = @ids;
  vnote($start, $verbose, "c:$count:$count articles to index");
 INDEX: for my $id (@ids) {
    my @files;
    my $got_files;
    # find the section
    my $article = $articles->getByPkey($id);
    next unless ($article->{listed} || $article->{flags} =~ /I/);
    next unless $article->is_linked;
    next if $article->{flags} =~ /[CN]/;
    my $section = $article;
    while ($section->{parentid} >= 1) {
      $section = $articles->getByPkey($section->{parentid});
      next INDEX if $section->{flags} =~ /C/;
    }
    my $id = $article->{id};
    my $indexas = $article->{level} > $max_level ? $article->{parentid} : $id;
    my $sectionid = $section->{id};
    eval "use $article->{generator}";
    $@ and die $@;
    my $gen = $article->{generator}->new(top=>$article, cfg=>$cfg);
    next unless $gen->visible($article) or $do_search{$sectionid};
    
    next if $dont_search{$sectionid};

    $article = $gen->get_real_article($article);

    unless ($article) {
      vnote($start, $verbose, "e:$id:Full article for $id not found");
      next;
    }
    
    vnote($start, $verbose, "i:$id:Indexing '$article->{title}'");
    
    my %fields;
    for my $field (sort { $scores{$b} <=> $scores{$a} } keys %scores) {

      next unless $scores{$field};
      # strip out markup
      my $text;
      if (exists $article->{$field}) {
	$text = $article->{$field};
      }
      else {
	if ($field =~ /^file_(.*)/) {
          my $file_field = $1;
          @files = $article->files unless $got_files++;
          $text = join "\n", map $_->{$file_field}, @files;
	}
      }
      #next if $text =~ m!^\<html\>!i; # I don't know how to do this (yet)
      if ($field eq 'body') {
	$gen->remove_block($articles, [], \$text);
	$text =~ s/[abi]\[([^\]]+)\]/$1/g;
      }

      next unless defined $text;

      $fields{$field} = $text;
    }
    $indexer->process_article($article, $section, $indexas, \%fields);
  }
  vnote($start, $verbose, "f::Article scan complete");
}

sub vnote {
  my ($start, $verbose, @text) = @_;

  $verbose or return;
  printf "%.3f:%s\n", time() - $start, "@text";
}
