# mix-in (or close) for classes that keep tags
# currently just articles
# the owner class should implement a tag_owner_type method
package BSE::TB::TagOwner;
use strict;
use BSE::TB::Tags;
use BSE::TB::TagMembers;

our $VERSION = "1.001";

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

# remove all tags
sub remove_tags {
  my ($self) = @_;

  BSE::TB::TagMembers->remove_owned_by($self);
}

sub tag_objects {
  my ($self) = @_;

  return BSE::TB::Tags->getSpecial(object_tags => $self->tag_owner_type, $self->id);
}

sub tags {
  my ($self) = @_;

  return map $_->name, $self->tag_objects;
}

sub tag_ids {
  my ($self) = @_;

  return map $_->{id}, BSE::DB->single->run("Tag_ids.by_owner", $self->tag_owner_type, $self->id);
}

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

1;
