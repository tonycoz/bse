#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.50:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use Articles;
use BSE::DB;
use Constants qw(:search);
use Carp;
use BSE::Cfg;
use BSE::Template;
use DevHelp::HTML qw':default popup_menu';
use BSE::Util::Tags;
use BSE::Request;

my $req = BSE::Request->new;
my $cfg = $req->cfg;

my $results_per_page = 10;

my $cgi = $req->cgi;
my $words = $cgi->param('q');
my $section = $cgi->param('s');
my $date = $cgi->param('d');
my $match_all = $cgi->param('match_all');
$section = '' if !defined $section;
$date = 'ar' if ! defined $date;
my @results;
my @terms; # terms as parsed by the search engine
my $case_sensitive;
if (defined $words && length $words) {
  $case_sensitive = $words ne lc $words;
  @results = getSearchResult($words, $section, $date, \@terms, $match_all);
}
else { 
  $words = ''; # so we don't return junk for the form default
}

my $page_count = int((@results + $results_per_page - 1)/$results_per_page);

my $page_number = $cgi->param('page') || 1;
$page_number = $page_count if $page_number > $page_count;

my $admin = $cgi->param('admin');
$admin = 0 if !defined $admin;

my @articles;
if (@results) {
  my $articles_start = ($page_number-1) * $results_per_page;
  my $articles_end = $articles_start + $results_per_page-1;
  $articles_end = $#results if $articles_end >= @results;

  if ($cfg->entry('search', 'keep_inaccessible')) {
    for my $entry (@results[$articles_start..$articles_end]) {
      my $article = Articles->getByPkey($entry->[0])
	or die "Cannot retrieve article $entry->[0]\n";
      push(@articles, $article);
    }
  }
  else {
    my %remove; # used later to remove the inaccessible from @results;
    # we need to check accessiblity on each article
    my $index = 0;
    my $seen = 0;
    while ($index < @results && $seen <= $articles_end) {
      my $id = $results[$index][0];
      my $article = Articles->getByPkey($id)
	or die "Cannot retrieve article $id\n";
      if ($req->siteuser_has_access($article)) {
	if ($seen >= $articles_start) {
	  push @articles, $article;
	}
	++$seen;
      }
      else {
	$remove{$id} = 1;
      }
      ++$index;
    }
    @results = grep !$remove{$_->[0]}, @results;
  }
}

$page_count = int((@results + $results_per_page - 1)/$results_per_page);

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

my %scores = map @$_, @results;

my $max_score = 0;
for my $score (values %scores) {
  $score > $max_score and $max_score = $score;
}

my %highlight_prefix;
my %highlight_suffix;
for my $type (qw(keyword author pageTitle file_displayName 
                 file_description file_notes)) {
  $highlight_prefix{$type} = 
    $cfg->entry('search highlight', "${type}_prefix", "<b>");
  $highlight_suffix{$type} = 
    $cfg->entry('search highlight', "${type}_suffix", "</b>");
}

my $page_num_iter = 0;

my $article_index = -1;
my $result_seq = ($page_number-1) * $results_per_page;
my $excerpt;
my $keywords;
my $author;
my $pageTitle;
my $words_re_str = '\b('.join('|', map quotemeta, @terms).')';
my $highlight_partial = $cfg->entryBool('search', 'highlight_partial', 1);
$words_re_str .= '\b' unless $highlight_partial;
my $words_re = qr/$words_re_str/i;
my @files;
my $file_index;
my $current_result;
my %acts;
%acts =
  (
   $req->dyn_user_tags(),
   iterate_results => 
   sub { 
     ++$result_seq;
     ++$article_index;
     if ($article_index < @articles) {
       $current_result = $articles[$article_index];
       my $found = 0;
       $excerpt = excerpt($current_result, \$found, \@terms);

       # match against the keywords
       $keywords = $current_result->{keyword};
       $keywords =~ s!$words_re!$highlight_prefix{keyword}$1$highlight_suffix{keyword}!g or $keywords = '';

       # match against the author
       $author = $current_result->{author};
       $author =~ s!$words_re!$highlight_prefix{author}$1$highlight_suffix{author}!g 
	 or $author = '';

       # match against the pageTitle
       $pageTitle = $current_result->{pageTitle};
       $pageTitle =~ s!$words_re!$highlight_prefix{pageTitle}$1$highlight_suffix{pageTitle}!g 
	 or $pageTitle = '';
       $req->set_article(result => $current_result);

       # match files
       @files = ();
       for my $file ($current_result->files) {
	 my $found;
	 my %fileout;
	 for my $field (qw(displayName description notes)) {
           my $prefix = $highlight_prefix{"file_$field"};
           my $suffix = $highlight_suffix{"file_$field"};
	   $fileout{$field. "_matched"} = $file->{$field} =~ /$words_re/;
	   ++$found if ($fileout{$field} = $file->{$field}) 
	     =~ s!$words_re!$prefix$1$suffix!g;
	 }
	 if ($found) {
	   $fileout{notes_excerpt} = 
	     excerpt($current_result, \$found, \@terms, 'file_notes', $file->{notes});
	   push @files, [ \%fileout, $file  ];
	 }
       }
       
       return 1;
     }
     else {
       $req->set_article(result => undef);

       return 0;
     }
   },
   result => 
   sub { 
     my $arg = shift;
     if ($arg eq 'score') {
       return sprintf("%.1f", 100.0 * $scores{$current_result->{id}} / $max_score);
     }
     return escape_html($current_result->{$arg});
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
   keywords => 
   sub { 
     $keywords
   },
   author => 
   sub { 
     $author
   },
   pageTitle => 
   sub { 
     $pageTitle
   },
   ifMatchfiles => sub { @files },
   matchfile_count => sub { @files },
   iterate_matchfiles_reset => sub { $file_index = -1 },
   iterate_matchfiles => sub { ++$file_index < @files },
   matchfile =>
   sub {
     my ($args) = @_;
     $file_index < @files or return '';
     my $file_entry = $files[$file_index];
     # already html escaped
     exists $file_entry->[0]{$args} and return $file_entry->[0]{$args};

     my $value = $file_entry->[1]{$args};
     defined $value or return '';

     escape_html($value);
   },

   ifResults => sub { scalar @results; },
   ifSearch => sub { defined $words and length $words },
   dateSelected => sub { $_[0] eq $date ? 'selected="selected"' : '' },
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
   terms => sub { escape_html($words) },
   resultSeq => sub { $result_seq },
   list => sub { popup_menu(-name=>'s', -id => 's',
			    -values=>\@sections,
			    -labels=>\%sections,
			    -default=>$section) },
   
   # result pages
   iterate_pages =>
   sub {
     return ++$page_num_iter <= $page_count;
   },
   page => sub { $page_num_iter },
   ifCurrentSearchPage => 
   sub { $page_num_iter == $page_number },
   pageurl => 
   sub {
     $ENV{SCRIPT_NAME} . "?q=" . escape_uri($words) . 
       "&amp;s=" . escape_uri($section) .
	 "&amp;d=" . escape_uri($date) .
	   "&amp;page=".$page_num_iter;
   },
   highlight_result => [ \&tag_highlight_result, \$current_result, $cfg ],
  );

my $template = $cgi->param('embed') ? 'include/search_results' : 'search';
BSE::Template->show_page($template, $cfg, \%acts);

undef $req;

sub tag_highlight_result {
  my ($rcurrent_result, $cfg, $arg) = @_;

  $$rcurrent_result 
    or return "** highlight_result must be in results iterator **";

  my $text = $$rcurrent_result->{$arg};
  defined $text or return '';

  $text = escape_html($text);

  my $prefix = $cfg->entry('search highlight', "${arg}_prefix", "<b>");
  my $suffix = $cfg->entry('search highlight', "${arg}_suffix", "</b>");

  $text =~ s/$words_re/$prefix$1$suffix/g;

  $text;
}

sub getSearchResult {
  my ($words, $section, $date, $terms, $match_all) = @_;

  my $searcher_class = $cfg->entry('search', 'searcher', 'BSE::Search::BSE');
  (my $searcher_file = $searcher_class . '.pm') =~ s!::!/!g;;
  require $searcher_file;
  my $searcher = $searcher_class->new(cfg => $cfg);
  return $searcher->search($words, $section, $date, $terms, $match_all, $req);
}

my %gens;

sub excerpt {
  my ($article, $found, $terms, $type, $text) = @_;

  my $generator = $article->{generator};

  $generator =~ /\S/ or confess "generator for $article->{id} is blank";

  eval "use $generator";
  confess "Cannot use $generator: $@" if $@;

  $gens{$generator} ||= $generator->new(admin=>$admin, cfg=>$cfg, top=>$article);

  return $gens{$generator}->excerpt($article, $found, $case_sensitive, $terms, $type, $text);
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
