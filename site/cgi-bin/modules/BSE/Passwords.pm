package BSE::Passwords;
use strict;

our $VERSION = "1.000";

# wrapper around using the BSE::Password classes

sub new_password_hash {
  my ($self, $password) = @_;

  my ($obj, $name) = $self->new_password_handler;

  return ( $obj->hash($password), $name );
}

sub check_password_hash {
  my ($self, $hash, $type, $password, $error) = @_;

  my $obj = $self->_load($type);
  unless ($obj) {
    $$error = "LOAD";
    return;
  }

  unless ($obj->check($hash, $password)) {
    $$error = "INVALID";
    return;
  }

  return 1;
}

sub new_password_handler {
  my ($self) = @_;

  my $cfg = BSE::Cfg->single;
  my @handlers = split /,/, $cfg->entry("basic", "passwords", "cryptSHA256,cryptMD5,crypt,plain");

  for my $handler (@handlers) {
    my $obj = $self->_load($handler);
    $obj and return ($obj, $handler);
  }

  require BSE::Password::Plain;
  return ( BSE::Password::Plain->new, "plain" );
}

sub _load {
  my ($self, $handler) = @_;

  my $class = "BSE::Password::\u$handler";
  my $file = "BSE/Password/\u$handler.pm";

  eval { require $file; 1 }
    or return;

  my $obj = $class->new
    or return;

  return $obj;
}

1;

