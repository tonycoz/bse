package BSE::Password::Plain;
use strict;

our $VERSION = "1.001";

sub new {
  my ($class) = @_;

  return bless {}, $class;
}

sub hash {
  my ($self, $password) = @_;

  die "Plain password hashing is not supported for new passwords";
}

sub check {
  my ($self, $hash, $password) = @_;

  return $hash eq $password;
}

1;
