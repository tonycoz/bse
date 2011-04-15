package BSE::UI::Search;
use strict;
use base 'BSE::UI::Dispatch';
use Articles;
use BSE::DB;
use Constants qw(:search);
use Carp;
use BSE::Cfg;
use BSE::Template;
use BSE::Util::HTML qw':default popup_menu';
use BSE::Util::Tags qw(tag_article);
use BSE::Request;

our $VERSION = "1.002";

my %actions =
  (
   search => 1,
  );

sub actions { \%actions }

sub default_action { 'search' }

sub req_search {
  my ($class, $req) = @_;

  my $cfg = $req->cfg;
    
  my $cgi = $req->cgi;
  my $results_per_page = int($cgi->param('pp') || 10);
  $results_per_page >= 1 or $results_per_page = 10;
  my $words = $cgi->param('q');
  my $section = $cgi->param('s');
  my $date = $cgi->param('d');
  my $admin = $cgi->param('admin') ? 1 : 0;
  my $match_all = $cgi->param('match_all');
  $section = '' if !defined $section;
  $date = 'ar' if ! defined $date;
  my @results;
  my @terms; # terms as parsed by the search engine
  my $case_sensitive;
  if (defined $words && length $words) {
    $case_sensitive = $words ne lc $words;
    @results = getSearchResult($req, $words, $section, $date, \@terms, $match_all);
  }
  else { 
    $words = ''; # so we don't return junk for the form default
  }
  
  my $page_count = int((@results + $results_per_page - 1)/$results_per_page);
  
  my $page_number = $cgi->param('page') || 1;
  $page_number = $page_count if $page_number > $page_count;
  
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
  
  for my $article (@articles) {
    my $generator = $article->{generator};
    eval "use $generator";
    my $gen = $generator->new(top=>$article, cfg=>$cfg);
    $article = $gen->get_real_article($article);
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
                 file_description file_notes summary description product_code)) {
    $highlight_prefix{$type} = 
      $cfg->entry('search highlight', "${type}_prefix", "<b>");
    $highlight_suffix{$type} = 
      $cfg->entry('search highlight', "${type}_suffix", "</b>");
  }
  
  my $page_num_iter = 0;
  
  my $article_index = -1;
  my $result_seq = ($page_number-1) * $results_per_page;
  my $excerpt;
  my %match_tags;
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
	 $excerpt = excerpt($cfg, $admin, $case_sensitive, $current_result, \$found, \@terms);
	 
	 $req->set_article(result => $current_result);
	 
	 for my $field (qw/pageTitle summary keyword description author product_code/) {
	   my $value = $current_result->{$field};
	   defined $value or $value = '';
	   $value =~ s!$words_re!$highlight_prefix{$field}$1$highlight_suffix{$field}!g 
	     or $value = '';
	   $match_tags{$field} = $value;
	 }
	 
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
	       excerpt($cfg, $admin, $case_sensitive, $current_result, \$found, \@terms, 'file_notes', $file->{notes});
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
       return tag_article($current_result, $cfg, $arg);
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
     keywords     => sub { $match_tags{keyword} },
     author       => sub { $match_tags{author} },
     pageTitle    => sub { $match_tags{pageTitle} },
     match_summary => sub { $match_tags{summary} },
     description  => sub { $match_tags{description} },
     product_code => sub { $match_tags{product_code} },
     
     ifMatchfiles => sub { @files },
     matchfile_count => sub { @files },
     matchfile_index => sub { $file_index },
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
       return $admin ? $current_result->{admin} : $current_result->link($cfg);
     },
     count => sub { scalar @results },
     multiple => sub { @results != 1 },
     terms => sub { escape_html($words) },
     resultSeq => sub { $result_seq },
     list => sub { popup_menu(-name=>'s', -id => 'search_s',
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
       my $work_words = $words;
       $ENV{SCRIPT_NAME} . "?q=" . escape_uri($work_words) .
	 "&amp;s=" . escape_uri($section) .
	   "&amp;d=" . escape_uri($date) .
	     "&amp;page=".$page_num_iter .
	       "&amp;pp=$results_per_page";
     },
     highlight_result =>
     [ \&tag_highlight_result, \$current_result, $cfg, $words_re ],
     admin_search => $admin,
    );
  
  my $template = $cgi->param('embed') ? 'include/search_results' : 'search';
  my $result = $req->dyn_response($template, \%acts);
  %acts = (); # remove any circular refs

  return $result;
}

sub tag_highlight_result {
  my ($rcurrent_result, $cfg, $words_re, $arg) = @_;

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
  my ($req, $words, $section, $date, $terms, $match_all) = @_;

  my $cfg = $req->cfg;
  my $searcher_class = $cfg->entry('search', 'searcher', 'BSE::Search::BSE');
  (my $searcher_file = $searcher_class . '.pm') =~ s!::!/!g;;
  require $searcher_file;
  my $searcher = $searcher_class->new(cfg => $cfg);
  return $searcher->search($words, $section, $date, $terms, $match_all, $req);
}

my %gens;

sub excerpt {
  my ($cfg, $admin, $case_sensitive, $article, $found, $terms, $type, $text) = @_;

  my $generator = $article->{generator};

  $generator =~ /\S/ or confess "generator for $article->{id} is blank";

  eval "use $generator";
  confess "Cannot use $generator: $@" if $@;

  $gens{$generator} ||= $generator->new(admin=>$admin, cfg=>$cfg, top=>$article);

  return $gens{$generator}->excerpt($article, $found, $case_sensitive, $terms, $type, $text);
}

1;
