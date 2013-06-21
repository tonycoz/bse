# mix-in (or close) for classes that keep tags
# currently just articles
# the owner row class should implement a tag_owner_type method
package BSE::TB::TagOwners;
use strict;
use BSE::TB::Tags;
use BSE::TB::TagMembers;

our $VERSION = "1.007";

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

=item fix_tag_deps($tags, $opts)

Given a list of tag names, remove any tags where it's parent tag isn't
present.

Accepts two parameters:

=over

=item *

C<$tags> - an arrayref of tags to clean up.

=item *

C<$opts> - an optional hash of options.  The only defined option is:

=over

=item *

C<deps> - a hash ref of loaded category dependencies.  This may be
modified when you call fix_tag_deps().

=back

=back

=cut

sub fix_tag_deps {
  my ($self, $tags, $opts) = @_;

  $opts ||= {};

  my $deps = $opts->{deps} || {};
  my $removed;
  my %tags = map { $_ => 1 } @$tags;
  do {
    $removed = 0;
    my @tags = keys %tags;
    for my $tag (@tags) {
      my ($cat) = BSE::TB::Tags->split_name($tag);
      unless ($deps->{$cat}) {
	$deps->{$cat} = [ $self->tag_category_deps("$cat:") ];
      }
      if (@{$deps->{$cat}} and
	  !grep $tags{$_}, @{$deps->{$cat}}) {
	delete $tags{$tag};
	++$removed;
      }
    }
  } while ($removed);

  return [ keys %tags ];
}

=item expand_tag_deps

Given a list of tags, make sure any tags they depend on are present.

Accepts two parameters:

=over

=item *

C<$tags> - an arrayref of tags to clean up.

=item *

C<$opts> - an optional hash of options.  The only defined option is:

=over

=item *

C<deps> - a hash ref of loaded category dependencies.  This may be
modified when you call fix_tag_deps().

=back

=back

=cut

sub expand_tag_deps {
  my ($self, $tags, $opts) = @_;

  $opts ||= {};

  my $deps = $opts->{deps} || {};
  my %tags = map { $_ => 1 } @$tags;
  my $added;
  do {
    $added = 0;
    my @tags = keys %tags;
    for my $tag (@tags) {
      my ($cat) = BSE::TB::Tags->split_name($tag);
      unless ($deps->{$cat}) {
	$deps->{$cat} = [ $self->tag_category_deps("$cat:") ];
      }
      if (@{$deps->{$cat}} and
	  !grep $tags{$_}, @{$deps->{$cat}}) {
	$tags{$deps->{$cat}[0]} = 1;
	++$added;
      }
    }
  } while ($added);

  return [ keys %tags ];
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

Each category entry contains:

=over

=item *

name - the category

=item *

ind - a uniquified category name

=item *

vals - an array reference of values for the category

=item *

nocat - true if this is a wrapper for a tag with no category

=back

Each value entry contains:

=over

=item *

name - the full name of the tag

=item *

val - the value of the tag

=item *

cat - the category name

=item *

count - the number of entries for this tag (if counts is supplied as
an input)

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
  defined $selected_tags && $selected_tags ne "" or $selected_tags = [];

  my $all_selected;
  if (defined $selected_tags) {
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

=item collection_with_tags($name, $tags, \%opts)

Request a variety of tagging information about a collection of
articles, the return value includes:

=over

=item *

objects - an array reference of objects

=item *

object_ids - an array reference on matching objects

=item *

extratags - arrayref of tags as tag objects for those objects that
passed the filter, but aren't in the set of selected tags.

=item *

members - arrayref tag membership of tag membership objects.  May
include membership for objects outside of those listed in objects.

=back

If C<$name> is a false value then the tags are checked over the
objects supplied in C<$opts{objects}>.

C<%opts> can contain any of:

=over

=item *

args - arrayref of extra arguments to pass to the C<$name> method.
Defaults to none.

=item *

objects - the objects, already fetched (optional).  These must be the
same objects, or a subset of the objects, returned by the C<$name>
method.  Required if C<$name> is false.

=item *

noobjects - don't populate objects in the result.  This is done as
optimization for those cases when the objects are not needed.  In some
cases the objects may be fetched anyway.

=item *

self - the object to call method C<$name> on.  Defaults to the object
C<collection_with_tags> is called on.

=item *

members - previously fetched tag membership objects

=item *

knowntags - previously fetched knowntags

=back

=cut

sub collection_with_tags {
  my ($self, $name, $tags, $opts) = @_;

  $opts ||= {};
  my $objects = $opts->{objects};
  my $members = $opts->{members};
  my $knowntags = $opts->{knowntags};
  my $workself = $opts->{self} || $self;
  my $args = $opts->{args} || [];

  my @tag_objects;
  my %known_tags;
  my %known_by_id;
  %known_tags = map { lc $_->name => $_ } @$knowntags if $knowntags;
  %known_by_id = map { lc $_->id => $_ } @$knowntags if $knowntags;
  for my $tag (@$tags) {
    my $obj = ref $tag
      ? $tag
	: $known_tags{lc $tag} || $self->rowClass->tag_by_name($tag);
    unless ($obj) {
      # tag isn't in the system, so it can't match
      return
	{
	 objects => [],
	 extratags => [],
	 members => [],
	 object_ids => [],
	 counts => {},
	};
    }
    push @tag_objects, $obj;
  }

  my $tag_info;
  my $tag_method;
  if ($name) {
    $tag_method = $name;
    # so for a collection "all_visible_products" the method is
    # "all_visible_product_tags"
    $tag_method =~ s/e?s$//;
    $tag_method .= "_tags";
  }
  if (!$members
      && $name
      && $workself->can($tag_method)) {
    $tag_info = $workself->$tag_method(@$args);
    $members = $tag_info->{members};
    @known_tags{map $_->id, @{$tag_info->{tags}}} = @{$tag_info->{tags}};
  }

  if ($objects || !$opts->{noobjects} || !$members) {
    my @out_objects;
    my @out_members;
    my %out_tags;
    my %counts_by_id;
    $objects ||= [ $workself->$name(@$args) ];

    if ($members) {
      my %by_obj_and_tag;
      for my $member (@$members) {
	$by_obj_and_tag{$member->owner_id}{$member->tag_id} = $member;
      }

    OBJECT:
      for my $obj (@$objects) {
	my $obj_tags = $by_obj_and_tag{$obj->id}
	  or next OBJECT;
	for my $tag (@tag_objects) {
	  $obj_tags->{$tag->id}
	    or next OBJECT;
	}
	push @out_objects, $obj;
	@out_tags{keys %$obj_tags} = ();
	push @out_members, values %$obj_tags;
	++$counts_by_id{$_} for keys %$obj_tags;
      }
    }
    else {
      # no member information, fetch tags by object
    OBJECT:
      for my $obj (@$objects) {
	my @obj_tag_members = $obj->tag_members;
	my %obj_tag_members = map { $_->tag_id => 1 } @obj_tag_members;
	for my $tag (@tag_objects) {
	  $obj_tag_members{$tag->id}
	    or next OBJECT;
	}
	push @out_objects, $obj;
	@out_tags{map $_->tag_id, @obj_tag_members} = ();
	push @out_members, @obj_tag_members;
	++$counts_by_id{$_->tag_id} for @obj_tag_members;
      }
    }
    delete @out_tags{map $_->id, @tag_objects};

    my @out_tags;
    my %counts;
    for my $tag_id (keys %out_tags) {
      my $tag = $known_by_id{$tag_id}
	|| BSE::TB::Tags->getByPkey($tag_id);
      push @out_tags, $tag;
      $counts{$tag->name} = $counts_by_id{$tag->id} || 0;
    }
    return
      {
       objects => \@out_objects,
       members => \@out_members,
       extratags => \@out_tags,
       object_ids => [ map $_->id, @out_objects ],
       counts => \%counts,
      };
  }
  else {
    # at this point $members contains membership objects for the
    # articles we care about.
    my %by_obj_and_tag;
    for my $member (@$members) {
      $by_obj_and_tag{$member->owner_id}{$member->tag_id} = $member;
    }
    my @object_ids;
    my %out_tags;
    my @out_members;
    my %counts_by_id;
  OBJECT:
    for my $object_id (keys %by_obj_and_tag) {
      my $obj_tags = $by_obj_and_tag{$object_id};
      for my $tag (@tag_objects) {
	$obj_tags->{$tag->id}
	  or next OBJECT;
      }
      push @object_ids, $object_id;
      @out_tags{keys %$obj_tags} = ();
      push @out_members, values %$obj_tags;
      ++$counts_by_id{$_} for keys %$obj_tags;
    }
    delete @out_tags{map $_->id, @tag_objects};
    my @out_tags;
    my %counts;
    for my $tag_id (keys %out_tags) {
      my $tag = $known_by_id{$tag_id} || BSE::TB::Tags->getByPkey($tag_id);
      push @out_tags, $tag;
      $counts{$tag->name} = $counts_by_id{$tag_id};
    }

    return
      {
       members => \@out_members,
       extratags => \@out_tags,
       object_ids => \@object_ids,
       counts => \%counts,
      };
  }
}

1;

=back

=head1 REQUIRED METHODS

=over

=item rowClass

Returns the name of the class (or an object of that class)
representing the items in the collection.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

L<BSE::TB::TagOwner>, L<Articles>, L<BSE::TB::Tags>,
L<BSE::TB::TagCategory>

=cut
