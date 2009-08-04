package Courier::AustraliaPost::Sea;

use strict;
use Courier::AustraliaPost;

our @ISA=qw(Courier::AustraliaPost);

sub new {
    my ($class, %args) = @_;
    return $class->SUPER::new(%args, type => "SEA");
}

sub name {
    "ap-sea"
}

sub description {
    "Australia Post Sea Service"
}

sub can_deliver {
    my ($self, %opts) = @_;

    my $country = $opts{country}
      or return 0;

    return 0 if lc $country eq "australia";

    return 1;
}

1;
