package BSE::Variables;
use strict;
use Scalar::Util qw(blessed);
use BSE::TB::Site;
use BSE::Util::HTML;

our $VERSION = "1.007";

sub _base_variables {
  my ($self, %opts) = @_;

  return
    (
     site => BSE::TB::Site->new,
     articles => \&_articles,
     products => \&_products,
     url => 
     ($opts{admin} || $opts{admin_links}
      ? sub { _url_common($_[0]->admin, $_[1]) }
      : sub { _url_common($_[0]->link, $_[1]) }
     ),
     admin => $opts{admin},
     admin_links => $opts{admin_links},
     dumper => sub {
       require Data::Dumper;
       return escape_html(Data::Dumper::Dumper(shift));
     },
     categorize_tags => \&_categorize_tags,
     date => \&_date_format,
     now => \&date_now,
     number => sub {
       require BSE::Util::Format;
       return BSE::Util::Format::bse_number(@_);
     },
    );
}

sub variables {
  my ($self, %opts) = @_;

  return
    +{
      $self->_base_variables(%opts),
     };
}

sub dyn_variables {
  my ($self, %opts) = @_;

  my $req = $opts{request} or die "No request parameter";
  my $cgi = $req->cgi;
  my $cart;
  return
    +{
      $self->_base_variables(%opts),
      paged => sub { return _paged($cgi, @_) },
      cart => sub {
	require BSE::Cart;
	$cart ||= BSE::Cart->new($req);
	return $cart;
      },
     };
}

sub _url_common {
  my ($base, $extras) = @_;

  if ($extras && ref $extras) {
    my @extras;
    for my $key (keys %$extras) {
      my $value = $extras->{$key};
      if (ref $value) {
	push @extras, map { "$key=" . escape_uri($_) } @$value;
      }
      else {
	push @extras, "$key=" . escape_uri($value);
      }
    }

    if (@extras) {
      $base .= $base =~ /\?/ ? "&" : "?";
      $base .= join("&", @extras);
    }
  }

  return $base;
}

sub _categorize_tags {
  my ($tags, $selected_tags, $opts) = @_;

  require Articles;

  if ($opts && $opts->{members} && !$opts->{counts}) {
    my %counts;
    my %tags = map { $_->id => $_->name } @$tags;
    for my $entry (@{$opts->{members}}) {
      ++$counts{$tags{$entry->tag_id}};
    }
    $opts->{counts} = \%counts;
  }

  return Articles->categorize_tags($tags, $selected_tags, $opts);
}

sub _paged {
  my ($cgi, $list, $opts) = @_;

  $opts ||= {};
  my $ppname = $opts->{ppname} || "pp";
  my $pp = $cgi->param($ppname) || $opts->{pp} || 20;
  my $pname = $opts->{pname} || "p";
  my $p = $cgi->param($pname) || 1;
  $p =~ /\A[0-9]\z/ or $p = 1;

  my $pcount = @$list ? int((@$list + $pp - 1) / $pp) : 1;

  $p > $pcount and $p = $pcount;
  my $startindex = ($p - 1 ) * $pp;
  my $endindex = $startindex + $pp - 1;
  $endindex > $#$list and $endindex = $#$list;

  my @pages;
  my $gap_name = $opts->{gap} || "...";
  my $gap = { page => $gap_name, link => 0, gap => 1 };
  my $pages_size = $opts->{pages_size} || 20;
  my $bcount = int(($pages_size - 1) * 2 / 3);
  if ($pcount <= $pages_size) {
    @pages = map +{ page => $_, gap => 0, link => $_ != $p }, 1 .. $pcount;
  }
  elsif ($p < $bcount) {
    @pages =
      (
       ( map +{ page => $_, gap => 0, link => $_ != $p }, 1 .. $bcount ),
       $gap,
       ( map +{ page => $_, gap => 0, link => 1 },
	 ($pcount - ($pages_size - $bcount) + 1) .. $pcount ),
      );
  }
  elsif ($p > $pcount - int($pages_size * 2 / 3)) {
    @pages =
      (
       ( map +{ page => $_, gap => 0, link => 1 },
	 1 .. ($pages_size - 1 - $bcount)),
       $gap,
       ( map +{ page => $_, gap => 0, link => $_ != $p },
	 ( $pcount - $bcount + 1 ) .. $pcount )
      );
  }
  else {
    my $ends = int(($pages_size - 2) / 4);
    my $mid_size = $pages_size - 2 - $ends * 2;
    my $mid_start = $p - int($mid_size / 2);
    my $mid_end = $mid_start + $mid_size - 1;
    @pages = 
      (
       ( map +{ page => $_, gap => 0, link => 1 }, 1 .. $ends ),
       $gap,
       ( map +{ page => $_, gap => 0, link => $_ != $p },
	 $mid_start .. $mid_end ),
       $gap,
       ( map +{ page => $_, gap => 0, link => 1 },
	 $pcount - $ends + 1 .. $pcount ),
      );
  }

  return
    {
     page => $p,
     pp => $pp,
     pagecount => $pcount,
     start => $startindex,
     end => $endindex,
     startnum => $startindex + 1,
     items => [ @{$list}[$startindex .. $endindex ] ],
     is_first_page => $p == 1,
     is_last_page => $p == $pcount,
     next_page => ( $p < $pcount ? $p + 1 : 0 ),
     previous_page => ($p > 1 ? $p - 1 : 0 ),
     pages => \@pages,
     pname => $pname,
     ppname => $ppname,
    };
}

sub _variable_class {
  my ($class) = @_;

  require Squirrel::Template;
  return Squirrel::Template::Expr::WrapClass->new($class);
}

{
  my $articles;
  sub _articles {
    unless ($articles) {
      require Articles;
      $articles = _variable_class("Articles");
    }

    return $articles;
  }
}

{
  my $products;
  sub _products {
    unless ($products) {
      require Products;
      $products = _variable_class("Products");
    }

    return $products;
  }
}

# format an SQL format date
sub _date_format {
  my ($format, $date) = @_;

  my ($year, $month, $day, $hour, $min, $sec) = 
    $date =~ /(\d+)\D+(\d+)\D+(\d+)(?:\D+(\d+)\D+(\d+)\D+(\d+))?/;
  $hour = $min = $sec = 0 unless defined $sec;
  $year -= 1900;
  --$month;
  # passing the isdst as 0 seems to provide a more accurate result than
  # -1 on glibc.
  require DevHelp::Date;
  return DevHelp::Date::dh_strftime($format, $sec, $min, $hour, $day, $month, $year, -1, -1, -1);
}

sub _date_now {
  my ($fmt) = @_;

  $fmt ||= "%d-%b-%Y";
  require DevHelp::Date;
  return DevHelp::Date::dh_strftime($fmt, localtime);
}

1;

=head1 NAME

BSE::Variables - commonly set variables

=head1 SYNOPSIS

  # in perl code
  require BSE::Variables;
  $foo->set_variable(bse => BSE::Variables->variables(%opts));

  # in templates
  <:.set level1 = bse.site.children :>
  <:= bse.url(article) | html :>
  <:= tagcats = bse.categorize_tags(article.tag_objects) :>
  <:.if bse.admin:>...
  <:= bse.dumper(somevar) :> lots of noise

=head1 DESCRIPTION

Common BSE functionality for use from the new template tags.

=head1 COMMON VALUES

=over

=item bse.site

a BSE::TB::Site object, behaves like an article in owning files and
images, and having children.w

=item bse.url(somearticle)

=item bse.url(somearticle, extraargs)

Return the article admin link in admin (or admin_links) mode,
otherwise the normal article link.

If supplied, C<extraargs> should be a hash containing extra arguments.

=item bse.admin

Return true in admin mode.

=item bse.admin_links

Return true in admin_links mode

=item dumper(value)

Dump the value in perl syntax using L<Data::Dumper>.

=item categorize_tags(tags)

Returns the given tags as a list of tag categories, each category has
a name (of the category) and a list of tags in that category.

=item articles

=item products

The article and product collections.

=item date(format, when)

Format an SQL date/time.

=item now(format)

Format the current date/time.

=back

=head1 DYNAMIC ONLY VARIABLES

=over

=item bse.pages(list)

=item bse.pages(list, options)

Paginate the contents of C<list>.

If C<options> is supplied it should be a hash optionally containing
any of the following keys:

=over

=item *

C<ppname> - the name of the items per page CGI parameter.  Default:
"pp".

=item *

C<pp> - the default number of items per page.  Default: 20.

=item *

C<p> - the name of the page number CGI parameter.  Default: "p".

=item *

C<gap> - the text for the C<page> value in the page list for gap
entries.  Default: "...".

=item *

C<pages_size> - the desired maximum number of entries in the pages
list.  Default: 20.  This should be at least 10.

=back

Returns a hash with the following keys:

=over

=item *

page - the current page number

=item *

pagecount - the number of pages.

=item *

pp - the number of items per page.

=item *

start - the start index within the original list for the items list.

=item *

end - the end index within the original list for the items list.

=item *

startnum - the starting number within the list for the items list.
Always C<startindex>+1.

=item *

items - a list of items for the current page.

=item *

is_first_page - true for the first page.

=item *

is_last_page - true for the last page.

=item *

next_page - the page number of the next page, 0 if none.

=item *

previous_page - the page number of the previous page, 0 if none.

=item *

pages - a list of pages, each with the keys:

=over

=item *

page - the page number or the gap value if this entry represents a
gap.

=item *

gap - true if this entry is a gap.

=item *

link - true if this entry should be a link.  false for gaps and the
current page.

=back

=item *

pname - the name of the page number parameter

=item *

ppname - the name of the items per page parameter

=back

=item bse.cart

The contents of the cart.  See L<BSE::Cart> for details.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
