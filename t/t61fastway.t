#!perl -w
use strict;
use Test::More;

BEGIN {
  eval "use XML::Simple; 1"
    or plan skip_all => "No XML::Simple";

  plan tests => 7;
}

use Courier::Fastway::Road;
use BSE::Shipping;

my %cfg_work = 
  (
   shipping => 
   {
    sourcepostcode => "4350",
    fastwayfranchisee => "TOO",
   },
   debug =>
   {
    fastway => 0,
   },
  );

my $cfg = bless \%cfg_work, "Test::Cfg";

my $cour = Courier::Fastway::Road->new(config => $cfg);
ok($cour, "make courier object");
ok($cour->can_deliver(country => "AU",
		      suburb => "Westmead",
		      postcode => "2145"), "can deliver to australia");
ok(!$cour->can_deliver(country => "NZ"),
   "can't deliver to NZ");

my $small_parcel = BSE::Shipping::Parcel->new
  (
   length => 100,
   width => 200,
   height => 200,
   weight => 800
  );

my $medium_parcel = BSE::Shipping::Parcel->new
  (
   length => 500,
   width => 400,
   height => 400,
   weight => 6000
  );

my $local_small_cost = $cour->calculate_shipping
  (
   parcels => [ $small_parcel ],
   postcode => 4405,
   suburb => "Dalby",
   country => "AU"
  );
ok($local_small_cost, "got a local small parcel cost");
like($local_small_cost, qr/^\d+$/, "it's an integer");

my $local_medium_cost = $cour->calculate_shipping
  (
   parcels => [ $medium_parcel ],
   postcode => 4405,
   suburb => "Dalby",
   country => "AU"
  );
ok($local_medium_cost, "got a local medium cost");
like($local_medium_cost, qr/^\d+$/, "it's an integer");

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $def) = @_;

  exists $self->{$section} or return $def;
  exists $self->{$section}{$key} or return $def;
  return $self->{$section}{$key};
}
