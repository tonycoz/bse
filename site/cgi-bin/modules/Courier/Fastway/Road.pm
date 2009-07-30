package Courier::Fastway::Road;

use strict;
use Courier::Fastway;

our @ISA=qw(Courier::Fastway);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "Road");
}

sub name {
    "Fastway Road Service"
}

1;
