package BSE::TB::AdminUser;
use strict;
use base qw(BSE::TB::AdminBase);

sub columns {
  return ($_[0]->SUPER::columns,
	  qw/base_id logon name password perm_map password_type/);
}

sub bases {
  return { base_id=>{ class=>'BSE::TB::AdminBase' } };
}

sub remove {
  my ($self) = @_;

  BSE::DB->run(deleteUserGroups => $self->{id});

  $self->SUPER::remove();
}

sub groups {
  my ($self) = @_;

  require BSE::TB::AdminGroups;

  BSE::TB::AdminGroups->getSpecial(forUser => $self->{id});
}

sub changepw {
  my ($self, $password) = @_;

  require BSE::Passwords;

  my ($hash, $type) = BSE::Passwords->new_password_hash($password);

  $self->set_password($hash);
  $self->set_password_type($type);

  1;
}

sub check_password {
  my ($self, $password, $error) = @_;

  require BSE::Passwords;
  return BSE::Passwords->check_password_hash($self->password, $self->password_type, $password, \$error);
}

1;

