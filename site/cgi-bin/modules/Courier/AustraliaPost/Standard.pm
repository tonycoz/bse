package Courier::AustraliaPost::Standard;

use strict;
use Courier::AustraliaPost;

our @ISA=qw(Courier::AustraliaPost);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "STANDARD");
}

sub name {
    "ap-standard"
}

sub description {
    "Australia Post: Standard";
}

1;
