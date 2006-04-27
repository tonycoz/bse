package BSE::Search::BSE;
use strict;
use Constants qw(:search);

use base 'BSE::Search::Base';

sub new {
  my ($class, %opts) = @_;

  return bless \%opts, $class;
}

sub get_term_matches {
  my ($term, $allow_wc, $section) = @_;

  my $dh = BSE::DB->single;

  my $sth;
  if ($SEARCH_AUTO_WILDCARD && $allow_wc) {
    $sth = $dh->stmt('searchIndexWC');
    $sth->execute($term."%")
      or die "Could not execute search: ",$sth->errstr;
  }
  else {
    $sth = $dh->stmt('searchIndex');
    $sth->execute($term)
      or die "Could not execute search: ",$sth->errstr;
  }
  
  my %matches;
  while (my $row = $sth->fetchrow_arrayref) {
    # skip any results that contain spaces if our term doesn't
    # contain spaces.  This loses wildcard matches which hit
    # phrase entries
    next if $term !~ /\s/ && $row->[0] =~ /\s/;
    my @ids = split ' ', $row->[1];
    my @scores = split ' ', $row->[3];
    if ($section) {
      # only for the section requested
      my @sections = split ' ', $row->[2];
      my @keep = grep { $sections[$_] == $section && $ids[$_] } 0..$#sections;
      @ids = @ids[@keep];
      @scores = @scores[@keep];
    }
    for my $index (0 .. $#ids) {
      $matches{$ids[$index]} += $scores[$index];
    }
  }

  return map [ $_, $matches{$_} ], keys %matches;
}

sub search {
  my ($self, $words, $section, $date, $terms, $match_all, $req) = @_;

  # canonical form
  $words =~ s/^\s+|\s+$//g;

  # array of [ term, unquoted, required, weight ]
  my @terms;
  my @exclude;
  while (1) {
    if ($words =~ /\G\s*-"([^"]+)"/gc
	|| $words =~ /\G\s*-'([^\']+)'/gc) {
      push @exclude, [ $1, 0 ];
    }
    elsif ($words =~ /\G\s*\+"([^"]+)"/gc
	|| $words =~ /\G\s*\+'([^\']+)'/gc) {
      push @terms, [ $1, 0, 1, 1 ];
    }
    elsif ($words =~ /\G\s*"([^"]+)"/gc
	|| $words =~ /\G\s*'([^']+)'/gc) {
      push(@terms, [ $1, 0, 0, 1 ]);
    }
    elsif ($words =~ /\G\s*-(\S+)/gc) {
      push @exclude, [ $1, 1 ];
    }
    elsif ($words =~ /\G\s*\+(\S+)/gc) {
      push(@terms, [ $1, 1, 1, 1 ]);
    }
    elsif ($words =~ /\G\s*(\S+)/gc) {
      push(@terms, [ $1, 1, 0, 1 ]);
    }
    else {
      last;
    }
  }
  
  @terms or return;

  if ($match_all) {
    for my $term (@terms) {
      $term->[2] = 1;
    }
  }

  # if the user entered a plain multi-word phrase
  if ($words !~ /["'+-]/ && $words =~ /\s/) {
    # treat it as if they entered it in quotes as well
    # giving articles with that phrase an extra score
    push(@terms, [ $words, 0, 0, 0.1 ]);
  }

  # disable wildcarding for short terms
  for my $term (@terms) {
    if ($term->[1] && length($term->[0]) < $SEARCH_WILDCARD_MIN) {
      $term->[1] = 0;
    }
  }

  my %scores;
  my %terms;
  for my $term (grep !$_->[2], @terms) {
    my @matches = get_term_matches($term->[0], $term->[1], $section);
    for my $match (@matches) {
      $scores{$match->[0]} += $match->[1] * $term->[3];
    }
  }
  my @required = grep $_->[2], @terms;
  my %delete; # has of id to 1
  if (@required) {
    my %match_required;
    for my $term (@required) {
      my @matches = get_term_matches($term->[0], $term->[1], $section);
      for my $match (@matches) {
	$scores{$match->[0]} += $match->[1];
	++$match_required{$match->[0]};
      }
    }
    for my $id (keys %scores) {
      if (!$match_required{$id} || $match_required{$id} != @required) {
	++$delete{$id};
      }
    }
  }
  for my $term (@exclude) {
    my @matches = get_term_matches($term->[0], $term->[1], $section);
    ++$delete{$_->[0]} for @matches;
  }

  delete @scores{keys %delete};

  return () if !keys %scores;

  # make sure we match the other requirements
  my $sql = "select id from article where ";
  $sql .= "(".join(" or ", map "id = $_", keys %scores).")";
  my $now = _sql_date(time);
  my $oneday = 24 * 3600;
  SWITCH: for ($date) {
    $_ eq 'ar' # been released
      && do {
	$sql .= " and $now between release and expire";
	last SWITCH;
      };
    /^r(\d+)$/ # released in last N days
      && do {
	$sql .= " and release > "._sql_date(time - $oneday * $1);
	last SWITCH;
      };
    /^e(\d+)$/ # expired in last N days
      && do {
	$sql .= " and expire > " . _sql_date(time - $oneday * $1) 
                   ." and expire <= $now";
	last SWITCH;
      };
    /^m(\d+)$/ # modified in last N days
      && do {
	$sql .= " and lastModified > " . _sql_date(time - $oneday * $1);
	last SWITCH;
      };
    $_ eq 'ae'
      && do {
	$sql .= " and expire < $now";
	last SWITCH;
	};
  }

  $sql .= " order by title";

  my $dh = BSE::DB->single;

  my $sth = $dh->{dbh}->prepare($sql)
    or die "Error preparing $sql: ",$dh->{dbh}->errstr;

  $sth->execute()
    or die "Cannot execute $sql: ",$sth->errstr;

  my @ids;
  my $row;
  push(@ids, $row->[0]) while $row = $sth->fetchrow_arrayref;

  @ids = sort { $scores{$b} <=> $scores{$a} } @ids;

  @$terms = map $_->[0], @terms;

  return map [ $_, $scores{$_} ], @ids;
}

sub _sql_date {
  my ($time) = @_;
  use POSIX qw(strftime);

  strftime("'%Y-%m-%d %H:%M'", localtime $time);
}

1;
