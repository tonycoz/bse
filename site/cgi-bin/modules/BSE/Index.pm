package BSE::Index;
use strict;
use Time::HiRes qw(time);
use Constants qw(@SEARCH_EXCLUDE @SEARCH_INCLUDE);
use Articles;

our $VERSION = "1.003";

my %default_scores =
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

sub new {
  my ($class, %opts) = @_;

  my $cfg = BSE::Cfg->single;
  unless ($opts{scores}) {
    my $scores = { %default_scores };
    for my $field (keys %$scores) {
      $scores->{$field} = $cfg->entry("search index scores", $field, $scores->{$field});
    }
    $opts{scores} = $scores;
  }
  $opts{start} = time;
  $opts{max_level} ||= $cfg->entry("search", "level", $Constants::SEARCH_LEVEL);

  return bless \%opts, $class;
}

sub indexer {
  my ($self) = @_;

  unless ($self->{indexer}) {
    my $cfg = BSE::Cfg->single;
    my $indexer_class = $cfg->entry('search', 'indexer', 'BSE::Index::BSE');
    (my $indexer_file = $indexer_class . ".pm") =~ s!::!/!g;
    require $indexer_file;

    $self->{indexer} = $indexer_class->new
      (
       cfg => $cfg,
       scores => $self->{scores},
       verbose => $self->{verbose},
      );
  }

  return $self->{indexer};
}

sub do_index {
  my ($self) = @_;

  my $indexer = $self->indexer;
  eval {
    $self->vnote("s1::Starting index");
    $indexer->start_index();
    $self->vnote("s2::Starting article scan");
    $self->make_index();
    $self->vnote("f2::Populating search index");
    $indexer->end_index();
    $self->vnote("f1::Indexing complete");
  };
  if ($@) {
    $self->_error("Indexing error: $@");
    return;
  }
  return 1;
}

sub make_index {
  my ($self) = @_;

  my %dont_search;
  my %do_search;
  @dont_search{@SEARCH_EXCLUDE} = @SEARCH_EXCLUDE;
  @do_search{@SEARCH_INCLUDE} = @SEARCH_INCLUDE;
  $self->vnote("s::Loading article ids");
  my @ids = Articles->allids;
  my $count = @ids;
  $self->vnote("c:$count:$count articles to index");
  my $cfg = BSE::Cfg->single;
  my $indexer = $self->indexer;

 INDEX: for my $id (@ids) {
    my @files;
    my $got_files;
    # find the section
    my $article = Articles->getByPkey($id);
    next unless $article;
    next unless ($article->{listed} || $article->{flags} =~ /I/);
    next unless $article->is_linked;
    next if $article->{flags} =~ /[CN]/;
    my $section = $article;
    while ($section->{parentid} >= 1) {
      $section = Articles->getByPkey($section->{parentid});
      next INDEX if $section->{flags} =~ /C/;
    }
    my $id = $article->{id};
    my $indexas = $article->{level} > $self->{max_level} ? $article->{parentid} : $id;
    my $sectionid = $section->{id};
    eval "use $article->{generator}";
    $@ and die $@;
    my $gen = $article->{generator}->new(top=>$article, cfg=>$cfg);
    next unless $gen->visible($article) or $do_search{$sectionid};
    
    next if $dont_search{$sectionid};

    $article = $gen->get_real_article($article);

    unless ($article) {
      $self->error("$id:Full article for $id not found");
      next;
    }

    $self->vnote("i:$id:Indexing '$article->{title}'");

    my %fields;
    my $scores = $self->{scores};
    for my $field (sort { $scores->{$b} <=> $scores->{$a} } keys %$scores) {

      next unless $self->{scores}{$field};
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
	$gen->remove_block("Articles", [], \$text);
	$text =~ s/[abi]\[([^\]]+)\]/$1/g;
      }

      next unless defined $text;

      $fields{$field} = $text;
    }
    $indexer->process_article($article, $section, $indexas, \%fields);
  }
  $self->vnote("f::Article scan complete");
}

sub error {
  my ($self, @msg) = @_;

  $self->_error($self->_time_passed, ":e:", @msg);
}

sub _error {
  my ($self, @error) = @_;

  if ($self->{error}) {
    $self->{error}->(@error);
  }
  else {
    print STDERR @error;
  }
}

sub _time_passed {
  my ($self) = @_;

  return sprintf("%.3f", time() - $self->{start});
}

sub vnote {
  my ($self, @msg) = @_;

  $self->_note($self->_time_passed, ":", @msg);
}

sub _note {
  my ($self, @msg) = @_;

  if ($self->{note}) {
    $self->{note}->(@msg);
  }
}
