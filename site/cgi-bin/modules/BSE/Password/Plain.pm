package BSE::Password::Plain;
use strict;

our $VERSION = "1.000";

sub new {
  my ($class) = @_;

  return bless {}, $class;
}

sub hash {
  my ($self, $password) = @_;

  return $password;
}

sub check {
  my ($self, $hash, $password) = @_;

  return $hash eq $password;
}

1;
