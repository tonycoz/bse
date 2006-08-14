#!perl -w
use strict;
use Test::More tests => 26;

++$|;

my $debug = 0;

my $gotmodule;
BEGIN { $gotmodule = use_ok('DevHelp::Payments::SecurePayXML'); }

my %cfg_good =
  (
   testmerchantid=>'ABC0001',
   testpassword=>'abc123',
   test=>1,
   debug => $debug,
  );

my $cfg = bless \%cfg_good, 'Test::Cfg';

my $payment = DevHelp::Payments::SecurePayXML->new($cfg);

ok($payment, 'make payment object');

my %req =
  (
   cardnumber => '4242424242424242',
   expirydate => '200612',
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

# try to create a periodic payment
my %add =
  (
   clientid => 'AAAA',
   expirydate => '12/06',
   cardnumber => '4242424242424242',
  );
$result = $payment->add_payment(%add);
ok($result, "got some sort of result");
ok($result->{success}, "successful!")
  or print "# failed add_payment: ",$result->{error}, "\n";
print "# payment id: $result->{paymentid}\n";
ok($result->{paymentid}, "got a payment id");

my $paymentid = $result->{paymentid};

my %trigger =
  (
   paymentid => $paymentid,
   amount => 1500,
  );

print "# trigger a payment\n";
$result = $payment->make_payment(%trigger);
ok($result, "got some sort of result");
ok($result->{success}, "success!");
ok($result->{receipt}, "check receipt");

print "# delete the payment\n";
my %delete =
  (
   paymentid => $paymentid
  );
$result = $payment->delete_payment(%delete);
ok($result, "got some sort of result");
ok($result->{success}, "success!")
  or print "# delete error: $result->{error}\n";

print "# try a bad triggered payment\n";
my %bad_trigger =
  (
   paymentid => $paymentid,
   amount => 1000,
  );
$result = $payment->make_payment(%bad_trigger);
ok($result, "got some sort of result");
ok(!$result->{success}, "shouldn't be successful");
print "# bad trigger error: $result->{error}\n";

my %bad_add =
  (
   clientid => 'BBBB',
   expirydate => '05/05',
   cardnumber => '4242424242424241',
  );
$result = $payment->add_payment(%bad_add);
ok($result, "got some sort of result");
ok(!$result->{success}, "should fail");
print "# bad add_payment: ",$result->{error}, "\n";

# try to fail one with a bad password
my %cfg_bad =
  (
   testmerchantid=>'ABC0001',
   testpassword=>'abc123x',
   test=>1,
   debug => $debug,
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
   debug => $debug,
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
