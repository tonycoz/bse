package Courier::Fastway::Satchel;

use strict;
use Courier::Fastway;

our @ISA=qw(Courier::Fastway);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "Satchel");
}

sub name {
    "fastway-satchel"
}

sub description {
    "Fastway Satchel Service"
}

1;
