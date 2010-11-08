package DevHelp::Payments::Test;
use strict;
use Carp 'confess';

our $VERSION = "1.000";

sub new {
  my ($class, $cfg) = @_;

  return bless { cfg => $cfg }, $class;
}

sub payment {
  my ($self, %args) = @_;

  my $cfg = $self->{cfg};

  for my $name (qw/orderno amount cardnumber expirydate ipaddress cvv/) {
    defined $args{$name}
      or confess "Missing $name argument";
  }

  my $currency = $args{currency};
  if (defined $currency && $currency ne 'AUD') {
    return
      {
       success => 0,
       error => 'Unknown currency',
       statuscode => 5,
      };
  }

  if (my $result = $cfg->entry('test payments', 'result')) {
    my ($code, $error) = split /;/, $result, 2;
    return 
      {
       success => 0,
       statuscode => $code,
       error => $error,
      };
  }

  my ($expyear, $expmonth) = $args{expirydate} =~ /^(\d\d\d\d)(\d\d)$/
    or return
      {
       success => 0,
       statuscode => 1,
       error => 'Invalid expiry date',
      };

  my ($nowyear, $nowmonth) = (localtime)[5, 4];
  $nowyear += 1900;
  ++$nowmonth;

  if ($expyear < $nowyear || $expyear == $nowyear && $expmonth < $nowmonth) {
    return
      {
       success => 0,
       statuscode => 1,
       error => 'Card expired',
      };
  }

  unless ($args{amount} =~ /^\d+$/ && $args{amount} > 0) {
    return
      {
       success => 0,
       statuscode => 2,
       error => 'Invalid amount',
      };
  }

  $args{cardnumber} =~ tr/0-9//cd;
  if ($args{cardnumber} eq '4111111111111100') {
    return
      {
       success => 1,
       statuscode => 0,
       error => '',
       receipt => "R$args{orderno}",
       transactionid => '',
      };
  }
  elsif ($args{cardnumber} =~ /(\d\d)$/) {
    return
      {
       success => 0,
       statuscode => 0+$1,
       error => "Synthetic error $1",
      };
  }
}

1;

=head1 NAME

DevHelp::Payments::Test - test payments driver

=head1 SYNOPSIS

  my $obj = DevHelp::Payments::Test->new($cfg);

  my $result = $obj->payment(orderno=>$order_number,
                             amount => $amount_in_cents,
                             cardnumber => $cc_number,
                             expirydate => $yyyymm,
                             ipaddress => $user_ip,
                             cvv => $cvv);
  if ($result->{success}) {
    print "Receipt: $result->{receipt}\n";
  }
  else {
    print "Error: $result->{error}\n";
  }

=head1 TESTING

This module provides mechanisms for testing credit card transactions.

To use it add 

  cardprocessor=DevHelp::Payments::Test

to the [shop] section of bse.cfg (or an includes config file.)

The amount, currency type, and card expiry date are all validated.

If the credit card number supplied is: 4111111111111100 the
transaction will succeed.

Otherwise the last 2 digits of the credit card number are used to
synthesize an error.

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

=back

