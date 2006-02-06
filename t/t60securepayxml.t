#!perl -w
use strict;
use Test::More tests => 14;

my $gotmodule;
BEGIN { $gotmodule = use_ok('DevHelp::Payments::SecurePayXML', ':all'); }

my %cfg_good =
  (
   testmerchantid=>'ABC0001',
   testpassword=>'abc123',
   test=>1,
   debug => 0,
  );

my $cfg = bless \%cfg_good, 'Test::Cfg';

my $payment = DevHelp::Payments::SecurePayXML->new($cfg);

ok($payment, 'make payment object');

my %req =
  (
   cardnumber => '4242424242424242',
   expirydate => '200605',
   amount => 1000,
   orderno => time,
  );

my $result = $payment->payment(%req);
ok($result, "got some sort of result");
ok($result->{success}, "successful!");
ok($result->{receipt}, "got a receipt: $result->{receipt}");

my %req_bad = 
  (
   cardnumber => '4242424242424242',
   expirydate => '200405', # out of date CC #
   amount => 1000, # on test server, cents returned as status
   orderno => time,
  );

$result = $payment->payment(%req_bad);
ok($result, "got some sort of result");
ok(!$result->{success}, "failed as expected");
ok($result->{error}, "got an error: $result->{error}");

# try to fail one with a bad password
my %cfg_bad =
  (
   testmerchantid=>'ABC0001',
   testpassword=>'abc123x',
   test=>1,
   debug => 0,
  );

$cfg = bless \%cfg_bad, 'Test::Cfg';

$payment = DevHelp::Payments::SecurePayXML->new($cfg);

$result = $payment->payment(%req);
ok($result, "got some sort of result");
ok(!$result->{success}, "failed as expected");
ok($result->{error}, "got an error: $result->{error}");

# try to fail one with a bad connectivity
my %cfg_bad2 =
  (
   testmerchantid=>'ABC0001',
   testpassword=>'abc123',
   testurl => 'https://undefined.develop-help.com/xmltest',
   test=>1,
   debug => 1,
  );

$cfg = bless \%cfg_bad2, 'Test::Cfg';

$payment = DevHelp::Payments::SecurePayXML->new($cfg);

$result = $payment->payment(%req);
ok($result, "got some sort of result");
ok(!$result->{success}, "failed as expected");
ok($result->{error}, "got an error: $result->{error}");

package Test::Cfg;

sub entry {
  my ($self, $section, $key, $def) = @_;

  $section eq 'securepay xml' or die;
  exists $self->{$key} or return $def;

  return $self->{$key};
}
