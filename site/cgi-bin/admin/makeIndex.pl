#!/usr/bin/perl -w
use strict;
use FindBin;
use lib "$FindBin::Bin/../modules";
use Articles;
use Constants qw($BASEDIR $MAXPHRASE $DATADIR @SEARCH_EXCLUDE @SEARCH_INCLUDE $SEARCH_LEVEL);
use BSE::DB;
use Generate;
use BSE::Cfg;
use Util 'refresh_to';
my $in_cgi = exists $ENV{REQUEST_METHOD};
if ($in_cgi) {
  #eval "use CGI::Carp qw(fatalsToBrowser)";
}

my $cfg = BSE::Cfg->new;
my $urlbase = $cfg->entryVar('site', 'url');

my $stopwords = "$DATADIR/stopwords.txt";

# load the stop words
open STOP, "< $stopwords"
  or die "Cannot open $stopwords: $!";
chomp(my @stopwords = <STOP>);
tr/\r//d for @stopwords; # just in case
my %stopwords;
@stopwords{@stopwords} = (1) x @stopwords;
close STOP;

my $articles = Articles->new;

# scores depending on where the term appears
# these may need some tuning
# preferably, keep these to single digits
my %scores =
  (
   title=>5,
   body=>3,
   keyword=>4,
   file_description => 0,
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

# key is phrase, value is hashref with $id -> $sectionid
my %index;
makeIndex($articles);

#use Data::Dumper;
#print Dumper(\%index);

my $dh = BSE::DB->single;
my $dropIndex = $dh->stmt('dropIndex')
  or die "No dropIndex member in BSE::DB";
my $insertIndex = $dh->stmt('insertIndex')
  or die "No insertIndex member in BSE::DB";

$dropIndex->execute()
  or die "Could not drop search index ",$dropIndex->errstr;

for my $key (sort keys %index) {
  my $word = $index{$key};
  # sort by reverse score so that if we overflow the field we
  # get the highest scoring matches
  my @ids = sort { $word->{$b}[1] <=> $word->{$a}[1] } keys %$word;
  my @sections = map { $_->[0] } @$word{@ids};
  my @scores = map { $_->[1] } @$word{@ids};
  #my @sections = map { $_->[0] } values %{$index{$key}};
  #my @scores = map { $_->[1] } values %{$index{$key}};

  $insertIndex->execute($key, "@ids", "@sections", "@scores")
    or die "Cannot insert into index: ", $insertIndex->errstr;
}

if ($in_cgi) {
  refresh_to("$urlbase/cgi-bin/admin/menu.pl");
}

sub makeIndex {
  my $articles = shift;
  my %dont_search;
  my %do_search;
  @dont_search{@SEARCH_EXCLUDE} = @SEARCH_EXCLUDE;
  @do_search{@SEARCH_INCLUDE} = @SEARCH_INCLUDE;
  INDEX: until ($articles->EOF) {
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
    my $gen = $article->{generator}->new(top=>$article);
    next unless $gen->visible($article) or $do_search{$sectionid};
    
    next if $dont_search{$sectionid};

    for my $field (sort { $scores{$b} <=> $scores{$a} } keys %scores) {

      next unless $scores{$field};
      # strip out markup
      my $text;
      if (exists $article->{$field}) {
	$text = $article->{$field};
      }
      else {
	if ($field eq 'file_description') {
	  my @files = $article->files;
	  $text = join "\n", map { @$_{qw/displayName description/} } @files;
	}
      }
      #next if $text =~ m!^\<html\>!i; # I don't know how to do this (yet)
      if ($field eq 'body') {
	$gen->remove_block($article, [], \$text);
	$text =~ s/[abi]\[([^\]]+)\]/$1/g;
      }

      next unless defined $text;

      # for each paragraph
      for my $para (split /\n/, $text) {
	my @words = split /\W+/, $para;
	my @buffer;

	for my $word (@words) {
	  if ($stopwords{lc $word}) {
	    process($indexas, $sectionid, $scores{$field}, @buffer) if @buffer;
	    @buffer = ();
	  }
	  else {
	    push(@buffer, $word);
	  }
	}
	process($indexas, $sectionid, $scores{$field}, @buffer) if @buffer;
      }
    }
  }
}

sub process {
  my ($id, $sectionid, $score, @words) = @_;
  
  for (my $start = 0; $start < @words; ++$start) {
    my $end = $start + $MAXPHRASE-1;
    $end = $#words if $end > $#words;
    
    for my $phrase (map { "@words[$start..$_]" } $start..$end) {
      if (!exists $index{lc $phrase}{$id}
	  || $score > $index{lc $phrase}{$id}[1]) {
	$index{lc $phrase}{$id} = [ $sectionid, $score ];
      }
      if (!exists $index{$phrase}{$id}
	  || $score > $index{$phrase}{$id}[1]) {
	$index{$phrase}{$id} = [ $sectionid, $score ];
      }
    }
  }
}

