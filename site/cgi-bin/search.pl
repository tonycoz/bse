#!/usr/bin/perl -w
use strict;
use CGI qw(:standard);
use FindBin;
use lib "$FindBin::Bin/modules";
use Articles;
use BSE::DB;
use Constants qw(:search);
use Carp;
use BSE::Cfg;
use BSE::Template;

my $cfg = BSE::Cfg->new;

my $results_per_page = 10;

my $dh = BSE::DB->single;

my $words = param('q');
my $section = param('s');
my $date = param('d');
$section = '' if !defined $section;
$date = 'ar' if ! defined $date;
my @results;
my @terms; # terms as parsed by the search engine
my $case_sensitive;
if (defined $words && length $words) {
  $case_sensitive = $words ne lc $words;
  @results = getSearchResult($words, $section, $date, \@terms);
}
else { 
  $words = ''; # so we don't return junk for the form default
}

my $page_count = int((@results + $results_per_page - 1)/$results_per_page);

my $page_number = param('page') || 1;
$page_number = $page_count if $page_number > $page_count;

my $admin = param('admin');
$admin = 0 if !defined $admin;

my @articles;
if (@results) {
  my $articles_start = ($page_number-1) * $results_per_page;
  my $articles_end = $articles_start + $results_per_page-1;
  $articles_end = $#results if $articles_end >= @results;

  for my $id (@results[$articles_start..$articles_end]) {
    my $article = Articles->getByPkey($id)
      or die "Cannot retrieve article $id\n";
    push(@articles, $article);
  }
}

# make an array of hashes (to preserve order)
my %excluded;
@excluded{@SEARCH_EXCLUDE} = @SEARCH_EXCLUDE;
my %included;
@included{@SEARCH_INCLUDE} = @SEARCH_INCLUDE;
my @sections = map { { $_->{id} => $_->{title} } } 
		     sort { $b->{displayOrder} <=> $a->{displayOrder} }
		       grep { ($_->{listed} || $included{$_->{id}}) 
                                && !$excluded{$_->{id}} }
			 Articles->getBy('level', 1);
unshift(@sections, { ""=>$SEARCH_ALL });
my %sections = map { %$_ } @sections;
# now a list of values ( in the correct order
@sections = map { keys %$_ } @sections;

my $page_num_iter = 0;

my $article_index = -1;
my $result_seq = ($page_number-1) * $results_per_page;
my $excerpt;
my $keywords;
my $words_re_str = '\b('.join('|', @terms).')\b';
my $words_re = qr/$words_re_str/i;
my %acts;
%acts =
  (
   iterate_results => 
   sub { 
     ++$result_seq;
     ++$article_index;
     if ($article_index < @articles) {
       my $found = 0;
       $excerpt = excerpt($articles[$article_index], \$found, @terms);

       # match against the keywords
       $keywords = $articles[$article_index]{keyword};
       $keywords =~ s!$words_re!<b>$1</b>!g or $keywords = '';

       return 1;
     }
     else {
       return 0;
     }
   },
   result => 
   sub { 
     return CGI::escapeHTML($articles[$article_index]{$_[0]});
   },
   date =>
   sub {
     my ($func, $args) = split ' ', $_[0];
     use POSIX 'strftime';
     exists $acts{$func}
       or return "** $func not found for date **";
     my $date = $acts{$func}->($args)
       or return '';
     my ($year, $month, $day) = $date =~ /(\d+)\D+(\d+)\D+(\d+)/;
     $year -= 1900;
     --$month;
     return strftime('%d-%b-%Y', 0, 0, 0, $day, $month, $year, 0, 0);
   },
   keywords => sub { $keywords },
   ifResults => sub { scalar @results; },
   ifSearch => sub { defined $words and length $words },
   dateSelected => sub { $_[0] eq $date ? 'selected' : '' },
   excerpt => 
   sub { 
     return $excerpt;
   },
   articleurl => 
   sub {
     my $name = $admin ? "admin" : "link";
     return $articles[$article_index]{$name};
   },
   count => sub { scalar @results },
   multiple => sub { @results != 1 },
   terms => sub { CGI::escapeHTML($words) },
   resultSeq => sub { $result_seq },
   list => sub { popup_menu(-name=>'s',
			    -values=>\@sections,
			    -labels=>\%sections) },
   
   # result pages
   iterate_pages =>
   sub {
     return ++$page_num_iter <= $page_count;
   },
   page => sub { $page_num_iter },
   ifCurrentPage => sub { $page_num_iter == $page_number },
   pageurl => 
   sub {
     $ENV{SCRIPT_NAME} . "?q=" . CGI::escape($words) . 
       "&s=" . CGI::escape($section) .
	 "&d=" . CGI::escape($date) .
	   "&page=".$page_num_iter;
   },
  );

BSE::Template->show_page('search', $cfg, \%acts);

sub getSearchResult {
  my ($words, $section, $date, $terms) = @_;

  # canonical form
  #$words = lc $words;
  $words =~ s/^\s+|\s+$//g;

  # array of [ term, unquoted ]
  my @terms;
 TERMS: {
    if ($words =~ /\G\s*"([^"]+)"/gc
	|| $words =~ /\G\s*'([^']+)'/gc) {
      push(@terms, [ $1, 0 ]);
      next TERMS;
    }
    if ($words =~ /\G\s*(\S+)/gc) {
      push(@terms, [ $1, 1 ]);
      next TERMS;
    }
  }

  # if the user entered a plain multi-word phrase
  if ($words !~ /["']/ && $words =~ /\s/) {
    # treat it as if they entered it in quotes as well
    # giving articles with that phrase an extra score
    push(@terms, [ $words, 0 ]);
  }

  # disable wildcarding for short terms
  for my $term (@terms) {
    if ($term->[1] && length($term->[0]) < $SEARCH_WILDCARD_MIN) {
      $term->[1] = 0;
    }
  }

  my %scores;
  my $sth;
  my %terms;
  for my $term (@terms) {
    if ($SEARCH_AUTO_WILDCARD && $term->[1]) {
      $sth = $dh->stmt('searchIndexWC');
      $sth->execute($term->[0]."%")
	or die "Could not execute search: ",$sth->errstr;
	
    }
    else {
      $sth = $dh->stmt('searchIndex');
      $sth->execute($term->[0])
	or die "Could not execute search: ",$sth->errstr;
    }

    while (my $row = $sth->fetchrow_arrayref) {
      # skip any results that contain spaces if our term doesn't
      # contain spaces.  This loses wildcard matches which hit
      # phrase entries
      next if $term->[0] !~ /\s/ && $row->[0] =~ /\s/;
      my @ids = split ' ', $row->[1];
      my @scores = split ' ', $row->[3];
      if ($section) {
	# only for the section requested
	my @sections = split ' ', $row->[2];
	my @keep = grep { $sections[$_] == $section && $ids[$_] } 0..$#sections;
	@ids = @ids[@keep];
	@scores = @scores[@keep];
      }
      for my $index (0..$#ids) {
	$scores{$ids[$index]} += $scores[$index];
      }
    }
  }

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
    $_ eq 'ae'
      && do {
	$sql .= " and expire < $now";
	last SWITCH;
	};
  }
  $sth = $dh->{dbh}->prepare($sql)
    or die "Error preparing $sql: ",$dh->{dbh}->errstr;

  $sth->execute()
    or die "Cannot execute $sql: ",$sth->errstr;

  my @ids;
  my $row;
  push(@ids, $row->[0]) while $row = $sth->fetchrow_arrayref;

  @ids = sort { $scores{$b} <=> $scores{$a} } @ids;

  @$terms = map $_->[0], @terms;

  return @ids;
}

sub _sql_date {
  my ($time) = @_;
  use POSIX qw(strftime);

  strftime("'%Y-%m-%d %H:%M'", localtime $time);
}

my %gens;

sub excerpt {
  my ($article, $found, @terms) = @_;

  my $generator = $article->{generator};

  $generator =~ /\S/ or confess "generator for $article->{id} is blank";

  eval "use $generator";
  confess "Cannot use $generator: $@" if $@;

  $gens{$generator} ||= $generator->new(admin=>$admin, cfg=>$cfg);

  return $gens{$generator}->excerpt($article, $found, $case_sensitive, @terms);
}

__END__

=head1 NAME

  search.pl - CGI script for searching for articles.

=head1 DESCRIPTION

This is the basic search engine for BSE.  It uses F<search.tmpl>
(generated from F<search_base.tmpl>) to format it's result pages.

=head1 TAGS

Please note that these tags are replace once the actual search is
done.  The tags defined in L<templates/"Base tags"> are replaced when
you choose I<Generate static pages> from the admin page.

=over 4

=item iterator ... results

Iterates over the articles for the current page of results.

=item result I<field>

Access to fields in the current search result article.

=item date I<which> I<field>

Formats the given field of the tag I<which> for display as a date.

=item keywords

Keywords for the current result article, if any keywords matches the
requested search.

=item ifResults

Conditional tag, true if the search found any matching articles.

=item ifSearch

Conditional tag, true if the user entered any search terms.

=item dateSelected I<datevalue>

The date value chosen by the user for the last search.  Used in a
<select> HTML tag to have the date field select the last value chosen
by the user.

=item excerpt

An excerpt of the body of the current search result, with search terms
highlighted.

=item articleurl

A link to the current search result article, taking admin mode into
account.

=item count

The total number of matches found.

=item ifMultiple

Conditional tag, true if more than one match was found.  This can be
used to improve the wording of descriptions of the search results.

=item terms

The entered search terms.

=item resultSeq

The number of the current search result (ie. the first found is 1, etc).

=item list

A drop-down list of searchable sections.

=item iterator ... pages

Iterates over page numbers of search results.

=item page

The current page number within the page number iterator.

=item ifCurrentPage

Conditional tag, true if the page in the page number iterator is the
displayed page of search results.  This can be used for formatting the
current page number differently (and not making it a link.)

=item pageurl

A link to the current page in the page number iterator.

=back

B<An example>

 ...
 <input type=text name=s value="<:terms:>">
 ...

 <:if Search:>
 <:if Results:>
  <dl>
  <:iterator begin results:>
  <dt><:resultSeq:> <a href="<:result url:>"><:result title:></a>
  <dd><:excerpt:>
  <:iterator end results:>
  </dl>
  <:iterator begin pages:>
   <:if CurrentPage:>
    <b><:page:></b>
   <:or CurrentPage:>
    <a href="<:pageurl:>"><:page:></a>
   <:eif CurrentPage:>
  <:iterator separator pages:>
  |
  <:iterator end pages:>
 <:or Results:>
 No articles matches your search.
 <:eif Results:>
 <:or Search:>
 <:eif Search:>

=cut
