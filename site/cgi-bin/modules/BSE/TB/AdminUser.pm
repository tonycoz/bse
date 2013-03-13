package BSE::TB::AdminUser;
use strict;
use base qw(BSE::TB::AdminBase);

our $VERSION = "1.006";

=head1 NAME

BSE::TB::AdminUser - represents an admin user.

=head1 METHODS

=over

=cut

sub columns {
  return ($_[0]->SUPER::columns,
	  qw/base_id logon name password perm_map password_type lockout_end/);
}

sub bases {
  return { base_id=>{ class=>'BSE::TB::AdminBase' } };
}

sub defaults {
  return
    (
     lockout_end => undef,
    );
}

sub remove {
  my ($self) = @_;

  BSE::DB->run(deleteUserGroups => $self->{id});

  $self->SUPER::remove();
}

=item groups()

return the groups the user is a member of.

=cut

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
  return BSE::Passwords->check_password_hash($self->password, $self->password_type, $password, $error);
}

sub link {
  my ($self) = @_;

  return BSE::Cfg->single->admin_url(adminusers => { a_showuser => 1, userid => $self->id });
}

sub describe {
  my ($self) = @_;

  return "Admin: " . $self->logon;
}

sub add_to_group {
  my ($self, $group) = @_;

  my $group_id = ref $group ? $group->id : $group;

  BSE::DB->run(addUserToGroup=>$self->{id}, $group_id);
}

sub remove_from_group {
  my ($self, $group) = @_;

  my $group_id = ref $group ? $group->id : $group;

  BSE::DB->run(delUserFromGroup=>$self->{id}, $group_id);
}

sub check_password_rules {
  my ($class, %opts) = @_;

  require BSE::Util::PasswordValidate;

  my %rules = BSE::Cfg->single->entries("admin user passwords");

  return BSE::Util::PasswordValidate->validate
    (
     %opts,
     rules => \%rules,
    );
}

sub password_check_fields {
  return qw(name);
}

=item locked_out

Return true if logons are disabled due to too many authentication
failures.

=cut

sub locked_out {
  my ($self) = @_;

  require BSE::Util::SQL;
  return $self->lockout_end
    && $self->lockout_end gt BSE::Util::SQL::now_datetime();
}

sub check_lockouts {
  my ($class, %opts) = @_;

  require BSE::Util::Lockouts;
  BSE::Util::Lockouts->check_lockouts
      (
       %opts,
       section => "admin user lockouts",
       component => "adminlogon",
       module => "logon",
       type => $class->lockout_type,
      );
}

sub unlock {
  my ($self, %opts) = @_;

  require BSE::Util::Lockouts;
  BSE::Util::Lockouts->unlock_user
      (
       %opts,
       user => $self,
       component => "adminlogon",
       module => "logon",
      );
}

sub unlock_ip_address {
  my ($class, %opts) = @_;

  require BSE::Util::Lockouts;
  BSE::Util::Lockouts->unlock_ip_address
      (
       %opts,
       component => "adminlogon",
       module => "logon",
       type => $class->lockout_type,
      );
}

sub lockout_type {
  "A";
}

=back

=cut

1;

