#!/usr/bin/perl -w
use strict;
use lib '../modules';
use Articles;
use Constants qw($BASEDIR $MAXPHRASE $URLBASE $DATADIR @SEARCH_EXCLUDE @SEARCH_INCLUDE $SEARCH_LEVEL);
use DatabaseHandle;
use Generate;
my $in_cgi = exists $ENV{REQUEST_METHOD};
if ($in_cgi) {
  eval "use CGI::Carp qw(fatalsToBrowser)";
}

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
  );

# if the level of the article is higher than this, store it's parentid 
# instead
my $max_level = $SEARCH_LEVEL;

# key is phrase, value is hashref with $id -> $sectionid
my %index;
makeIndex($articles);

#use Data::Dumper;
#print Dumper(\%index);

my $dh = DatabaseHandle->single;
my $dropIndex = $dh->{dropIndex}
  or die "No dropIndex member in DatabaseHandle";
my $insertIndex = $dh->{insertIndex}
  or die "No insertIndex member in DatabaseHandle";

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
  print "Refresh: 0; url=\"$URLBASE/admin/\"\n";
  print "Content-Type: text/html\n\n<html></html>\n";
}

sub makeIndex {
  my $articles = shift;
  my %dont_search;
  my %do_search;
  @dont_search{@SEARCH_EXCLUDE} = @SEARCH_EXCLUDE;
  @do_search{@SEARCH_INCLUDE} = @SEARCH_INCLUDE;
  until ($articles->EOF) {
    # find the section
    my $article = $articles->getNext;
    my $section = $article;
    while ($section->{parentid} >= 1) {
      $section = $articles->getByPkey($section->{parentid});
    }
    my $id = $article->{id};
    my $indexas = $article->{level} > $max_level ? $article->{parentid} : $id;
    my $sectionid = $section->{id};
    eval "use $article->{generator}";
    $@ and die $@;
    my $gen = $article->{generator}->new;
    next unless $gen->visible($article) or $do_search{$sectionid};
    
    next if $dont_search{$sectionid};

    for my $field (sort { $scores{$b} <=> $scores{$a} } keys %scores) {
      # strip out markup
      my $text = $article->{$field};
      #next if $text =~ m!^\<html\>!i; # I don't know how to do this (yet)
      if ($field eq 'body') {
	Generate->remove_block(\$text);
	$text =~ s/[abi]\[([^\]]+)\]/$1/g;
      }

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

