package BSE::TB::PriceTiers;
use strict;
use base 'Squirrel::Table';
use BSE::TB::PriceTier;

our $VERSION = "1.000";

sub rowClass { 'BSE::TB::PriceTier' }

1;
