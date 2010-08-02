package BSE::Password::Crypt;
use strict;

sub new {
  my ($class) = @_;

  return bless {}, $class;
}

sub _salt {
  return join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64]
}

sub hash {
  my ($self, $password) = @_;

  my $salt = $self->_salt;

  return crypt($password, $salt);
}

sub check {
  my ($self, $hash, $password) = @_;

  return crypt($password, $hash) eq $hash;
}

1;
