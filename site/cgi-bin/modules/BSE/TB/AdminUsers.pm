package BSE::TB::AdminUsers;
use strict;
use base 'Squirrel::Table';
use BSE::TB::AdminUser;

our $VERSION = "1.000";

sub rowClass {
  return 'BSE::TB::AdminUser';
}

sub make {
  my ($self, %opts) = @_;

  require BSE::Passwords;
  my $password = delete $opts{password};
  my ($hash, $type) = BSE::Passwords->new_password_hash($password);

  $opts{password} = $hash;
  $opts{password_type} = $type;

  return $self->SUPER::make(%opts);
}

1;
