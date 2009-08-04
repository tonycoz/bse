package Courier::AustraliaPost::Express;

use strict;
use Courier::AustraliaPost;

our @ISA=qw(Courier::AustraliaPost);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "EXPRESS");
}

sub name {
    "ap-express"
}

sub description {
    "Australia Post Express Service"
}

sub can_deliver {
    my ($self, %opts) = @_;

    my $country = $opts{country}
      or return 0;

    return 0 if lc $country ne "australia";

    return 1;
}

1;
