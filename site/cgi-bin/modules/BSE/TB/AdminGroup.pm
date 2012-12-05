package BSE::TB::AdminGroup;
use strict;
use base qw(BSE::TB::AdminBase);

our $VERSION = "1.002";

sub columns {
  return ($_[0]->SUPER::columns,
	  qw/base_id name description perm_map template_set/ );
}

sub bases {
  return { base_id=>{ class=>'BSE::TB::AdminBase' } };
}

sub defaults {
  return
    (
     type => "g",
     description => "",
     perm_map => "",
     template_set => "",
    );
}

sub remove {
  my ($self) = @_;

  BSE::DB->run(deleteGroupUsers => $self->{id});

  $self->SUPER::remove();
}

sub members {
  my ($self) = @_;

  return BSE::TB::AdminGroups->group_members($self->id);
}

sub has_member_id {
  my ($self, $id) = @_;

  my ($entry) = BSE::DB->query(bseAdminGroupMember => $self->id, $id);

  return defined $entry;
}

1;
