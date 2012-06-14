# mix-in (or close) for classes that keep tags
# currently just articles
# the owner row class should implement a tag_owner_type method
package BSE::TB::TagOwners;
use strict;
use BSE::TB::Tags;
use BSE::TB::TagMembers;

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

our $VERSION = "1.002";

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

  return BSE::DB->query
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

1;

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=head1 SEE ALSO

L<BSE::TB::TagOwner>, L<Articles>, L<BSE::TB::Tags>,
L<BSE::TB::TagCategory>

=cut
