# mix-in (or close) for classes that keep tags
# currently just articles
# the owner row class should implement a tag_owner_type method
package BSE::TB::TagOwners;
use strict;
use BSE::TB::Tags;
use BSE::TB::TagMembers;

our $VERSION = "1.004";

=head1 NAME

BSE::TB::TagOwners - mixin for collections that have tags on their members.

=head1 SYNOPSIS

  use base 'BSE::TB::TagOwners';

=head1 DESCRIPTION

Provides a mixin to collections such as L<Articles> for access to tag
information.

=head1 METHODS

=over

=cut

=item getTagByName($name)

Retrieve the tag object for the given tag name.

=cut

sub getTagByName {
  my ($self, $name) = @_;

  return BSE::TB::Tags->getByName($self->rowClass->tag_owner_type, $name);
}

=item getByTag($tag)

Retrieve objects within the collection (such as articles) that have
the given tag.

=cut

# return articles that use the given tag
sub getByTag {
  my ($self, $tag) = @_;

  return $self->getSpecial(byTag => $tag->id);
}

=item getIdsByTag($tag)

Retrieve object ids for objects within the collection with the given
tag.

=cut

sub getIdsByTag {
  my ($self, $tag) = @_;

  return BSE::TB::TagMembers->getColumnBy(owner_id => [ tag_id => $tag->id ]);
}

=item all_tags

Retrieve all tags specified for the collection.

=cut

sub all_tags {
  my ($self, @more_rules) = @_;
  return BSE::TB::Tags->getBy2
    (
     [ 
      [ owner_type => $self->rowClass->tag_owner_type ],
      @more_rules
     ],
     { order => "cat, val" },
    );
}

=item all_tag_categories

Retrieve a list of all tag categories.

=cut

sub all_tag_categories {
  my ($self, @more_rules) = @_;

  return map $_->{cat}, BSE::DB->query
    (
     'TagOwners.allCats' => $self->rowClass->tag_owner_type
    );
}

=item tag_category($catname)

Return a L<tag category object|BSE::TB::TagCategory> for the given
category name, creating it if necessary.

=cut

sub tag_category {
  my ($self, $catname) = @_;

  require BSE::TB::TagCategories;
  my ($cat) = BSE::TB::TagCategories->getBy
    (
     cat => $catname,
     owner_type => $self->rowClass->tag_owner_type,
    );
  unless ($cat) {
    $cat = BSE::TB::TagCategories->make
      (
       cat => $catname,
       owner_type => $self->rowClass->tag_owner_type,
      );
  }

  return $cat;
}

=item tag_category_deps($name)

Return the categories and tags the category C<$name> depends on.

This is more efficient than C<< tag_category($name)->deps >>.

=cut

sub tag_category_deps {
  my ($self, $catname) = @_;

  require BSE::TB::TagCategories;
  my ($cat) = BSE::TB::TagCategories->getBy
    (
     cat => $catname,
     owner_type => $self->rowClass->tag_owner_type,
    ) or return;

  return $cat->deps;
}

=item categorize_tags(\@tag_names, $selected, $opts)

Categorize and sorts the supplied tag names, returning an arrayref of
tag categories.

C<$selected> can be an array ref of selected tags, in which case only
those tags with a parent in C<@$selected> will be returned.

C<$selected> can be C<"*"> in which case all tags are always returned.

If C<$selected> is undef categorize() behaves as if it were an empty
array reference.

If supplied, C<$opts> should be a hash reference, with any of the
following keys:

=over

=item *

counts - a hash reference of counts of matching objects for tags in
C<@tag_names>.

=item *

onlyone - if a category is from a selected tag then that category will
not be in the result.

=back

=cut

sub categorize_tags {
  my ($self, $tags, $selected_tags, $opts) = @_;

  require Scalar::Util;
  my @tag_names = map
    {
      Scalar::Util::blessed($_)
	? $_->name : ref $_
	  ? $_->{name} : $_
	} @$tags;

  my $counts = $opts->{counts} || {};
  my $only_one = $opts->{onlyone} || 0;
  my $only_cat = $opts->{onlycat};

  my %selected_cats;
  defined $selected_tags or $selected_tags = [];

  my $all_selected;
  if ($selected_tags) {
    if (ref $selected_tags) {
      %selected_cats = map { lc("$_:") => 1 }
	map { lc ((BSE::TB::Tags->split_name($_))[0]) }
	  @$selected_tags;
    }
    else {
      # only meaningful for dependencies
      $all_selected = $selected_tags eq '*';
    }
  }

  my %cats;
 TAG:
  for my $tag (@tag_names) {
    my $count = $counts->{$tag} || 0;
    my ($cat, $val) = BSE::TB::Tags->split_name($tag);
    my $ind = lc(length $cat ? "$cat:" : $val);
    my $can_cat = lc $ind;

    if ($only_one && length $cat && $selected_cats{$can_cat}) {
      next TAG;
    }

    if (!$only_cat || $cat =~ /$only_cat/) {
      unless ($cats{$ind}) {
	$cats{$ind} =
	  {
	   name => $cat,
	   ind => $ind,
	   vals => [],
	   nocat => (length($cat) == 0),
	  };
      }
      push @{$cats{$ind}{vals}}, 
	{
	 name => $tag,
	 val => $val,
	 cat => $cat,
	 count => $count,
	};
    }
  }

  unless ($all_selected) {
    my %selected_tags = map { lc() => 1 } @$selected_tags;
    my @all_cats = grep /:$/, keys %cats;
  CAT: for my $cat (@all_cats) {
      my @deps = $self->tag_category_deps($cat)
	or next CAT;
      for my $dep (@deps) {
	if ($selected_cats{lc $dep} || $selected_tags{lc $dep}) {
	  next CAT;
	}
      }
      delete $cats{$cat};
    }
  }

  # sort each value set
  for my $cat (values %cats) {
    my $newvals =  [ sort { lc($a->{val}) cmp lc($b->{val}) } @{$cat->{vals}} ];
    $cat->{vals} = $newvals;
    $cat->{tags} = $newvals;
  }

  my $cats =
    [
     sort
     {
       $b->{nocat} <=> $a->{nocat}
	 || $a->{ind} cmp $b->{ind}
     } values %cats
    ];

  return $cats;
}

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

L<BSE::TB::TagOwner>, L<Articles>, L<BSE::TB::Tags>,
L<BSE::TB::TagCategory>

=cut
