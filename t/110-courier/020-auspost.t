#!perl -w
use strict;
use Test::More tests => 27;

use Courier::AustraliaPost::Standard;
use Courier::AustraliaPost::Air;
use Courier::AustraliaPost::Sea;
use BSE::Shipping;

my %cfg_work = 
  (
   shipping => 
   {
    sourcepostcode => "4350",
   },
   debug =>
   {
    auspost => 0
   },
  );

my $cfg = bless \%cfg_work, "Test::Cfg";

my $std = Courier::AustraliaPost::Standard->new(config => $cfg);
my $air = Courier::AustraliaPost::Air->new(config => $cfg);
my $sea = Courier::AustraliaPost::Sea->new(config => $cfg);

ok($std, "make standard courier object");
ok($std->can_deliver(country => "AU",
		      suburb => "Westmead",
		      postcode => "2145"), "can deliver to australia");
ok(!$std->can_deliver(country => "NZ"),
   "can't deliver to NZ");

my $tiny_parcel = BSE::Shipping::Parcel->new
  (
   length => 50,
   width => 20,
   height => 20,
   weight => 200
  );
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
   height => 300,
   weight => 6000
  );

my $local_tiny_cost = $std->calculate_shipping
  (
   parcels => [ $tiny_parcel ],
   postcode => 4405,
   suburb => "Dalby",
   country => "AU"
  );
ok($local_tiny_cost, "got a local tiny parcel cost")
  or diag $std->error_message;
like($local_tiny_cost, qr/^\d+$/, "it's an integer");
print "# $local_tiny_cost\n";

my $local_small_cost = $std->calculate_shipping
  (
   parcels => [ $small_parcel ],
   postcode => 4405,
   suburb => "Dalby",
   country => "AU"
  );
ok($local_small_cost, "got a local small parcel cost")
  or diag $std->error_message;
like($local_small_cost, qr/^\d+$/, "it's an integer");
print "# $local_small_cost\n";

my $local_medium_cost = $std->calculate_shipping
  (
   parcels => [ $medium_parcel ],
   postcode => 4405,
   suburb => "Dalby",
   country => "AU"
  );
ok($local_medium_cost, "got a local medium cost")
  or diag $std->error_message;
like($local_medium_cost, qr/^\d+$/, "it's an integer");
print "# $local_medium_cost\n";
cmp_ok($local_tiny_cost, "<=", $local_small_cost, "tiny < small");
cmp_ok($local_small_cost, "<=", $local_medium_cost, "small < medium");

# longer distance
my $nsw_medium_cost = $std->calculate_shipping
  (
   parcels => [ $medium_parcel ],
   postcode => 2145,
   suburb => "Westmead",
   country => "AU"
  );

ok($nsw_medium_cost, "got a nsw medium cost");
like($nsw_medium_cost, qr/^\d+$/, "it's an integer");
print "# $nsw_medium_cost\n";
cmp_ok($local_medium_cost, "<=", $nsw_medium_cost, "local <= nsw");

# longest
my $perth_medium_cost = $std->calculate_shipping
  (
   parcels => [ $medium_parcel ],
   postcode => 6000,
   suburb => "Perth",
   country => "AU"
  );

ok($perth_medium_cost, "got a perth medium cost");
like($perth_medium_cost, qr/^\d+$/, "it's an integer");
print "# $perth_medium_cost\n";
cmp_ok($nsw_medium_cost, "<=", $perth_medium_cost, "nsw <= perth");

# international
my $us_medium_cost_air = $air->calculate_shipping
  (
   parcels => [ $medium_parcel ],
   postcode => 6000,
   suburb => "Perth",
   country => "US"
  );

ok($us_medium_cost_air, "got a US medium cost");
like($us_medium_cost_air, qr/^\d+$/, "it's an integer");
print "# $us_medium_cost_air\n";
cmp_ok($perth_medium_cost, "<=", $us_medium_cost_air, "perth <= us air");

my $us_medium_cost_sea = $sea->calculate_shipping
  (
   parcels => [ $medium_parcel ],
   postcode => 6000,
   suburb => "Perth",
   country => "US"
  );

ok($us_medium_cost_sea, "got a US medium cost");
like($us_medium_cost_sea, qr/^\d+$/, "it's an integer");
print "# $us_medium_cost_sea\n";
cmp_ok($perth_medium_cost, "<=", $us_medium_cost_sea, "perth <= us sea");

# too big
my $too_long = BSE::Shipping::Parcel->new
  (
   length => 1060,
   width => 100,
   height => 100,
   weight => 200
  );
my $too_long_cost = $std->calculate_shipping
  (
   parcels => [ $too_long ],
   postcode => 2145,
   suburb => "Westmead",
   country => "AU",
  );
is($too_long_cost, undef, "too long returns undef");
ok($std->error_message, "some error set");

my $big_girth = BSE::Shipping::Parcel->new
  (
   length => 4000,
   width => 300,
   height => 500,
   weight => 200
  );

my $big_girth_cost = $std->calculate_shipping
  (
   parcels => [ $big_girth ],
   postcode => 2145,
   suburb => "Westmead",
   country => "AU",
  );
is($too_long_cost, undef, "big girth returns undef");
ok($std->error_message, "some error set");

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $def) = @_;

  exists $self->{$section} or return $def;
  exists $self->{$section}{$key} or return $def;
  return $self->{$section}{$key};
}
