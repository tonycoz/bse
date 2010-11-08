package BSE::Index::BSE;
use strict;
use base 'BSE::Index::Base';
use BSE::DB;
use Constants qw($DATADIR $MAXPHRASE);

our $VERSION = "1.000";

sub new {
  my ($class, %opts) = @_;

  my $self = bless \%opts, $class;

  $self->{dh} = BSE::DB->single;
  $self->{dropIndex} = $self->{dh}->stmt('dropIndex')
    or die "No dropIndex member in BSE::DB";
  $self->{insertIndex} = $self->{dh}->stmt('insertIndex')
    or die "No insertIndex member in BSE::DB";
  $self->{index} = {};

  $self->{decay_multiplier} = 0.4;

  $self->{wordre} = $self->{cfg}->entry("search", "wordre", "\\w+");

  return $self;
}

sub start_index {
  my $self = shift;

  my $stopwords = "$DATADIR/stopwords.txt";

  # load the stop words
  open STOP, "< $stopwords"
    or die "Cannot open $stopwords: $!";
  chomp(my @stopwords = <STOP>);
  tr/\r//d for @stopwords; # just in case
  my %stopwords;
  @stopwords{@stopwords} = (1) x @stopwords;
  close STOP;
  $self->{weights} = {};

  return 1;
}

sub process_article {
  my ($self, $article, $section, $indexas, $fields) = @_;

  $self->{weights}{$indexas} ||= {};
  for my $field (sort { $self->{scores}{$b} <=> $self->{scores}{$a} }
		 keys %$fields) {
    my $word_re = $self->{cfg}->entry("search", "wordre_$field", $self->{wordre});
    my $text = $fields->{$field};
    my $score = $self->{scores}{$field};
    my %seen; # $seen{phrase} non-zero if seen for this field
    
    # for each paragraph
    for my $para (split /\n/, $text) {
      my @words;
      while ($para =~ /($word_re)/g) {
	push @words, $1;
      }
      my @buffer;
      
      for my $word (@words) {
	if ($self->{stopwords}{lc $word}) {
	  $self->process($indexas, $section->{id}, $score, $self->{weights}{$indexas}, \%seen,
			 @buffer) if @buffer;
	  @buffer = ();
	}
	else {
	  push(@buffer, $word);
	}
      }
      $self->process($indexas, $section->{id}, $score, $self->{weights}{$indexas}, \%seen,
		     @buffer) if @buffer;
    }
    if ($field eq 'product_code' && $text) {
      $self->process($indexas, $section->{id}, $score, $self->{weights}{$indexas}, \%seen, $text);
    }
  }
}

sub process {
  my ($self, $id, $sectionid, $score, $weights, $seen, @words) = @_;
  
  for (my $start = 0; $start < @words; ++$start) {
    my $end = $start + $MAXPHRASE-1;
    $end = $#words if $end > $#words;
    
    for my $phrase (map { "@words[$start..$_]" } $start..$end) {
      if (lc $phrase ne $phrase && !$seen->{lc $phrase}++) {
	if (exists $self->{index}{lc $phrase}{$id}) {
	  $weights->{lc $phrase} *= $self->{decay_multiplier};
	  $self->{index}{lc $phrase}{$id}[1] += 
	    $score * $weights->{lc $phrase};
	}
	else {
	  $weights->{lc $phrase} = 1.0;
	  $self->{index}{lc $phrase}{$id} = [ $sectionid, $score ];
	}
      }
      if (!$seen->{$phrase}++) {
	if (exists $self->{index}{$phrase}{$id}) {
	  $weights->{$phrase} *= $self->{decay_multiplier};
	  $self->{index}{$phrase}{$id}[1] += 
	    $score * $weights->{$phrase};
	}
	else {
	  $weights->{$phrase} = 1.0;
	  $self->{index}{$phrase}{$id} = [ $sectionid, $score ];
	}
      }
    }
  }
}

sub end_index {
  my $self = shift;

  $self->{dropIndex}->execute()
    or die "dropIndex failed: ", $self->{dropindex}->errstr, "\n";

  my $insertIndex = $self->{insertIndex};
  for my $key (sort keys %{$self->{index}}) {
    my $word = $self->{index}{$key};
    # sort by reverse score so that if we overflow the field we
    # get the highest scoring matches
    my @ids = sort { $word->{$b}[1] <=> $word->{$a}[1] } keys %$word;
    my @sections = map { $_->[0] } @$word{@ids};
    my @scores = map { $_->[1] } @$word{@ids};
    
    $insertIndex->execute($key, "@ids", "@sections", "@scores")
      or die "Cannot insert into index: ", $insertIndex->errstr;
  }
}

1;
