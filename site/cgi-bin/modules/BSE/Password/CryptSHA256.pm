package BSE::Password::CryptSHA256;
use strict;
use base "BSE::Password::Crypt";

sub new {
  my ($class) = @_;

  crypt("test", '$5$00000000') eq '$5$00000000$rlV/Cvf6KAPRr28eKJSvYDnUm9rmJztOXHH0jx7zhnB'
    or return;

  return $class->SUPER::new();
}

sub _salt {
  return '$5$' . join "",
    ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[map rand 64, 1..16]
}

1;
