package Courier::AustraliaPost::Sea;

use strict;
use Courier::AustraliaPost;

our @ISA=qw(Courier::AustraliaPost);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "SEA");
}

sub name {
    "Australia Post: Sea"
}

1;
