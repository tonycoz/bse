# mix-in (or close) for classes that keep tags
# currently just articles
# the owner row class should implement a tag_owner_type method
package BSE::TB::TagOwners;
use strict;
use BSE::TB::Tags;
use BSE::TB::TagMembers;

our $VERSION = "1.001";

sub getTagByName {
  my ($self, $name) = @_;

  return BSE::TB::Tags->getByName($self->rowClass->tag_owner_type, $name);
}

# return articles that use the given tag
sub getByTag {
  my ($self, $tag) = @_;

  return $self->getSpecial(byTag => $tag->id);
}

sub getIdsByTag {
  my ($self, $tag) = @_;

  return BSE::TB::TagMembers->getColumnBy(owner_id => [ tag_id => $tag->id ]);
}

1;
