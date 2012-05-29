package BSE::Variables;
use strict;
use Scalar::Util qw(blessed);
use BSE::TB::Site;

our $VERSION = "1.001";

sub variables {
  my ($self, %opts) = @_;
  my $site;
  return
    {
     site => BSE::TB::Site->new,
     url => 
     ($opts{admin} || $opts{admin_links}
      ? sub { $_[0]->admin }
      : sub { $_[0]->link }
     ),
     admin => $opts{admin},
     admin_links => $opts{admin_links},
     dumper => sub {
       require Data::Dumper;
       return escape_html(Data::Dumper::Dumper(shift));
     },
     categorize_tags => \&_categorize_tags,
    };
}

sub _categorize_tags {
  my ($tags) = @_;

  $DB::single = 1;
  require BSE::TB::Tags;
  my %cats;
  for my $tag (@$tags) {
    my $work = blessed $tag ? $tag->json_data : $tag;
    my $cat = lc $tag->{cat};
    unless ($cats{$cat}) {
      $cats{$cat} =
	{
	 name => $tag->{cat},
	 tags => [],
	};
    }
    push @{$cats{$cat}{tags}}, $tag;
  }

  for my $cat (values %cats) {
    @{$cat->{tags}} = sort { lc $a->{val} cmp lc $b->{val} } @{$cat->{tags}};
  }

  return [ sort { lc $a->{name} cmp $b->{name} } values %cats ];
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
  <:= url(article) | html :>
  <:= tagcats = bse.categorize_tags(article.tag_objects) :>
  <:.if bse.admin:>...
  <:= dumper(somevar) :> lots of noise

=head1 DESCRIPTION

Common BSE functionality for use from the new template tags.

=over

=item bse.site

a BSE::TB::Site object, behaves like an article in owning files and
images, and having children.w

=item bse.url(somearticle)

Return the article admin link in admin (or admin_links) mode,
otherwise the normal article link.

=item bse.admin

Return true in admin mode.

=item bse.admin_links

Return true in admin_links mode

=item dumper(value)

Dump the value in perl syntax using L<Data::Dumper>.

=item categorize_keys(tags)

Returns the given tags as a list of tag categories, each category has
a name (of the category) and a list of tags in that category.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut
