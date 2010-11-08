package BSE::TB::SiteUserGroup;
use strict;
use base 'Squirrel::Row';
use constant OWNER_TYPE => "G";

our $VERSION = "1.000";

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

  # remove any members
  BSE::DB->single->run(siteuserGroupDeleteAllMembers => $self->{id});

  # remove any article permissions
  # note: this may leave an article dynamic that doesn't need to be
  # but I don't care much
  BSE::DB->single->run(siteuserGroupDeleteAllPermissions => $self->{id});

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

sub contains_user {
  my ($self, $user) = @_;

  my $user_id = ref $user ? $user->{id} : $user;

  my @membership = BSE::DB->single->query(siteuserMemberOfGroup => 
					  $user_id, $self->{id});

  return scalar @membership;
}

sub file_owner_type {
  return OWNER_TYPE;
}

sub files {
  my ($self) = @_;

  require BSE::TB::OwnedFiles;
  return BSE::TB::OwnedFiles->getBy(owner_type => OWNER_TYPE,
				    owner_id => $self->id);
}

1;
