#!perl -w
use strict;
use Test::More tests => 17;

++$|;

my $debug = 1;

my $gotmodule;
BEGIN { $gotmodule = use_ok('DevHelp::Payments::Eway'); }

my %cfg_good =
  (
   test=>1,
   debug => $debug,
  );

my $cfg = bless \%cfg_good, 'Test::Cfg';

my $payment = DevHelp::Payments::Eway->new($cfg);

ok($payment, 'make payment object');

{
  my %req =
    (	
     cardnumber => '4444333322221111',
     expirydate => '200708',
     nameoncard => "Joseph Bloe",
     amount => 1000,
     orderno => time,
     cvv => "123",
    );

  my $result = $payment->payment(%req);
  ok($result->{success}, "successful");
  ok($result->{receipt}, "got a receipt");
  ok($result->{transactionid}, "got a transaction id");
}

{
  my %req =
    (	
     cardnumber => '4444333322221111',
     expirydate => '200708',
     nameoncard => "Joseph Bloe",
     amount => 1000,
     orderno => time,
     cvv => "123",
     currency => "AUD",
    );

  my $result = $payment->payment(%req);
  ok($result->{success}, "successful with AUD");
  ok($result->{receipt}, "got a receipt");
  ok($result->{transactionid}, "got a transaction id");
}

{ # supply everything
  my %req =
    (	
     cardnumber => '4444333322221111',
     expirydate => '200708',
     nameoncard => "Joseph Bloe",
     amount => 1000,
     orderno => time,
     cvv => "123",
     currency => "AUD",
     firstname => "Joseph",
     lastname => "Bloe",
     address1 => "Unit 1",
     address2 => "56 Unknown Pde",
     suburb => "Sydney",
     postcode => "2345",
     state => "NSW",
     countrycode => "AU",
     email => 'test@example.com',
     description => "Test transaction",
     ipaddress => "127.0.0.1",
    );

  my $result = $payment->payment(%req);
  ok($result->{success}, "successful with details");
  ok($result->{receipt}, "got a receipt");
  ok($result->{transactionid}, "got a transaction id");
}

{
  my %req =
    (
     cardnumber => '4242424242424242',
     expirydate => '200708',
     nameoncard => "Joseph Bloe",
     amount => 1000,
     orderno => time,
     cvv => "321",
    );
  my $result = $payment->payment(%req);
  ok(!$result->{success}, "failure (bad card number)");
  ok($result->{statuscode}, "got an error code");
  like($result->{error}, qr/credit card/, "error should mention credit card");
}

{
  my %req =
    (
     cardnumber => '4444333322221111',
     expirydate => '200708',
     nameoncard => "Joseph Bloe",
     amount => 1001,
     orderno => time,
     cvv => "321",
    );
  my $result = $payment->payment(%req);
  ok(!$result->{success}, "failure (generated error)");
  like($result->{statuscode}, qr/[0-9]+/, "got a numeric error code");
  like($result->{error}, qr/^Refer to Issuer/, "match expected message");
}

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $def) = @_;

  $section eq 'eway payments' or die;
  exists $self->{$key} or return $def;

  return $self->{$key};
}
