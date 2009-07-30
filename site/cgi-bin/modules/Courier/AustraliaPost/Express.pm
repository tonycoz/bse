package Courier::AustraliaPost::Express;

use strict;
use Courier::AustraliaPost;

our @ISA=qw(Courier::AustraliaPost);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "EXPRESS");
}

sub name {
    "Australia Post: Express"
}

1;
