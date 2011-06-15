package BSE::TB::TagMembers;
use strict;
use base 'Squirrel::Table';
use BSE::TB::TagMember;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::TagMember';
}

sub remove_by_tag {
  my ($class, $owner, $tag) = @_;
  BSE::DB->single->run("TagMembers.removeByTag",
		       $owner->tag_owner_type, $owner->id, $tag->id);
}

sub remove_owned_by {
  my ($class, $owner) = @_;

  BSE::DB->single->run("TagMembers.remove_owned_by" =>
		       $owner->tag_owner_type, $owner->id);
}

1;
