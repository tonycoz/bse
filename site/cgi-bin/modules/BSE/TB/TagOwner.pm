# mix-in (or close) for classes that keep tags
# currently just articles
# the owner class should implement a tag_owner_type method
package BSE::TB::TagOwner;
use strict;
use BSE::TB::Tags;
use BSE::TB::TagMembers;

our $VERSION = "1.003";

=head1 NAME

BSE::TB::TagOwner - mixin for objects with tags

=head1 SYNOPSIS

  my $article = ...;

  $article->set_tags([ qw/tag1 tag2/ ], \$error);
  $article->remove_tags;

  my @tags = $article->tag_objects;
  my @tag_names = $article->tags;
  my @tag_ids = $article->tag_ids;

  if ($article->has_tags([ "tag1", "tag2" ])) {
    ...
  }

=head1 DESCRIPTION

This class is a mix-in that implements tags for the mixed-into object.

=head1 METHODS PROVIDED

=over

=item set_tags(\@tags, \$error)

Set the specified tags on the object, replacing all existing tags.

=cut

sub set_tags {
  my ($self, $rtags, $rerror) = @_;

  my @current_tags = $self->tag_objects;
  my %current = map { $_->canon_name => $_ } @current_tags;
  my %remove = %current;
  my %save;
  my %add;
  for my $name (@$rtags) {
    my $work = BSE::TB::Tags->name($name, $rerror);
    defined $work or return;

    my $lower = lc $work;
    if ($current{$lower}) {
      delete $remove{$lower};
      if (!$save{$lower} && $name ne $current{$lower}->name) {
	$save{$lower} = $name;
      }
    }
    else {
      $add{$lower} = $name;
    }
  }

  for my $add (values %add) {
    # look for or make the tag
    my $tag = BSE::TB::Tags->getByName($self->tag_owner_type, $add);
    if ($tag) {
      if ($tag->name ne $add && !$save{lc $add}) {
	$current{lc $add} = $tag;
	$save{lc $add} = $add;
      }
    }
    else {
      $tag = BSE::TB::Tags->make_with_name($self->tag_owner_type, $add);
    }

    # add the reference
    BSE::TB::TagMembers->make
	(
	 owner_type => $self->tag_owner_type,
	 owner_id => $self->id,
	 tag_id => $tag->id,
	);
  }

  for my $save (keys %save) {
    my $new_name = $save{$save};
    my $tag = $current{$save};
    $tag->set_name($new_name);
    $tag->save;
  }

  # remove any leftovers
  for my $remove (values %remove) {
    BSE::TB::TagMembers->remove_by_tag($self, $remove);
  }

  return 1;
}

=item remove_tags

Remove all tags from the object.

=cut

sub remove_tags {
  my ($self) = @_;

  BSE::TB::TagMembers->remove_owned_by($self);
}

=item tag_objects

Return all existing tags on the object as tag objects.

=cut

sub tag_objects {
  my ($self) = @_;

  return BSE::TB::Tags->getSpecial(object_tags => $self->tag_owner_type, $self->id);
}

=item tags

Returns all existing tags on the object as tag names.

=cut

sub tags {
  my ($self) = @_;

  return map $_->name, $self->tag_objects;
}

=item tag_ids

Returns all existing tags on the object as tag ids.

=cut

sub tag_ids {
  my ($self) = @_;

  return map $_->{id}, BSE::DB->single->run("Tag_ids.by_owner", $self->tag_owner_type, $self->id);
}

=item tag_members

Return all tag membership links for the object.

=cut

sub tag_members {
  my ($self) = @_;

  require BSE::TB::TagMembers;
  return BSE::TB::TagMembers->getBy
    (
     owner_id => $self->id,
     owner_type => $self->tag_owner_type,
    );
}

=item has_tags(\@tags)

Check that all of the specified tags are on the object.

=cut

sub has_tags {
  my ($self, $rtags) = @_;

  my %my_tag_ids = map { $_ => 1 } $self->tag_ids;

  # make sure we have objects, if there's no tag, we don't have that
  # tage and can immediately return false
  for my $tag (@$rtags) {
    my $work = $tag;
    unless (ref $work) {
      $work = BSE::TB::Tags->getByName($self->tag_owner_type, $tag)
	or return;
    }

    $my_tag_ids{$tag->id}
      or return;
  }

  return 1;
}

=item tag_by_name

Return the tag (if any) by name for this object type.

Returns an empty list if no such tag is found.

=cut

sub tag_by_name {
  my ($self, $name) = @_;

  my ($tag) = BSE::TB::Tags->getByName($self->tag_owner_type, $name)
    or return;

  return $tag;
}

=item collection_with_tags()

This is a wrapper for L<BSE::TB::TagOwners/collection_with_tags()>
that passes $self as the C<self> parameter in \%opts.

=cut

sub collection_with_tags {
  my ($self, $name, $tags, $opts) = @_;

  return $self->tableClass->collection_with_tags
    (
     $name,
     $tags,
     {
      ($opts ? %$opts : ()),
      self => $self,
     },
    );
}

1;

__END__

=back

=head1 REQUIRED METHODS

These need to be implemented by the class that wants tags.

=over

=item tag_owner_type

Return a short constant string identifying owner class of the tags.

=item id

The numeric id of the specific owner object of the tags.

=item tableClass

The name of the class for collections of the tag owner.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=cut

