package BSE::Password::CryptMD5;
use strict;
use base "BSE::Password::Crypt";

sub new {
  my ($class) = @_;

  crypt("test", '$1$00000000') eq '$1$00000000$/6RgkLRMOYgcMlYPGNjSy.'
    or return;

  return $class->SUPER::new();
}

sub _salt {
  return '$1$' . join "",
    ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[map rand 64, 1..8]
}

1;
