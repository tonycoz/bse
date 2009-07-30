package Courier::AustraliaPost::Air;

use strict;
use Courier::AustraliaPost;

our @ISA=qw(Courier::AustraliaPost);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "AIR");
}

sub name {
    "ap-air"
}

sub description {
    "Australia Post Air Service"
}

1;
