package BSE::TB::SiteUserGroup;
use strict;
use base 'Squirrel::Row';

sub columns {
  qw(id name);
}

sub primary { 'id' }

sub valid_fields {
  my ($class) = @_;

  return
    (
     name =>
     {
      description=>'Group Name',
      rules=>'required;no_star_at_front',
     },
    );
}

sub valid_rules {
  my ($class) = @_;

  return
    (
     no_star_at_front =>
     {
      nomatch => qr/^\*/,
      error=>'Group names may not start with *',
     },
    );
}

sub remove {
  my ($self) = @_;

  # remove any permissions and members for this group
  print STDERR "** FIXME ", __FILE__, " ", __LINE__, "\n";

  # remove any members
  BSE::DB->single->run(siteuserGroupDeleteAllMembers => $self->{id});

  $self->SUPER::remove();
}

sub member_ids {
  my ($self) = @_;

  map $_->{id}, BSE::DB->single->query(siteuserGroupMemberIds => $self->{id});
}

sub add_member {
  my ($self, $id) = @_;

  eval {
    BSE::DB->single->run(siteuserGroupAddMember => $self->{id}, $id);
  };
}

sub remove_member {
  my ($self, $id) = @_;

  BSE::DB->single->run(siteuserGroupDeleteMember => $self->{id}, $id);
}

1;
