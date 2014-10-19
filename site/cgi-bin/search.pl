#!/usr/bin/perl -w
# -d:ptkdb
BEGIN { $ENV{DISPLAY} = '192.168.32.54:0.0' }
use strict;
use FindBin;
use lib "$FindBin::Bin/modules";
use BSE::DB;
use BSE::Request;
use BSE::Template;
use Carp 'confess';
use BSE::UI::Search;

$SIG{__DIE__} = sub { confess $@ };

my $req = BSE::Request->new;

my $result = BSE::UI::Search->dispatch($req);

BSE::Template->output_result($req, $result);

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
