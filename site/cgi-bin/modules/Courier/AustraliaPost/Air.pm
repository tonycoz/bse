package Courier::AustraliaPost::Air;

our $VERSION = "1.000";

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

sub can_deliver {
    my ($self, %opts) = @_;

    my $country = $opts{country}
      or return 0;

    return 0 if uc $country eq "AU";

    return 1;
}

1;
