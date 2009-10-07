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
    "Australia Post Standard Service";
}

sub can_deliver {
    my ($self, %opts) = @_;

    my $country = $opts{country}
      or return 0;

    return 0 if uc $country ne "AU";

    return 1;
}

1;
