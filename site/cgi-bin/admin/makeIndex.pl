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
my $in_cgi = exists $ENV{REQUEST_METHOD};
if ($in_cgi) {
  #eval "use CGI::Carp qw(fatalsToBrowser)";
}

my $cfg = BSE::Cfg->new;
my $urlbase = $cfg->entryVar('site', 'url');

my $articles = Articles->new;

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
my $indexer = $indexer_class->new(cfg => $cfg, scores => \%scores);
eval {
  $indexer->start_index();
  makeIndex($articles);
  $indexer->end_index();
};
if ($@) {
  print STDERR "Indexing error: $@\n";
}

if ($in_cgi) {
  refresh_to_admin($cfg, "/cgi-bin/admin/menu.pl");
}

sub makeIndex {
  my $articles = shift;
  my %dont_search;
  my %do_search;
  @dont_search{@SEARCH_EXCLUDE} = @SEARCH_EXCLUDE;
  @do_search{@SEARCH_INCLUDE} = @SEARCH_INCLUDE;
  INDEX: until ($articles->EOF) {
    my @files;
    my $got_files;
    # find the section
    my $article = $articles->getNext;
    next unless ($article->{listed} || $article->{flags} =~ /I/);
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
}

