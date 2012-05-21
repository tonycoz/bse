package BSE::Shop::PaymentTypes;
use strict;

our $VERSION = "1.000";

use Exporter qw(import);

our @EXPORT_OK = qw(PAYMENT_CC PAYMENT_CHEQUE PAYMENT_CALLME PAYMENT_MANUAL PAYMENT_PAYPAL payment_types);

our @EXPORT = grep /^PAYMENT_/, @EXPORT_OK;

our %EXPORT_TAGS =
  (
   default => \@EXPORT,
  );

use constant PAYMENT_CC => 0;
use constant PAYMENT_CHEQUE => 1;
use constant PAYMENT_CALLME => 2;
use constant PAYMENT_MANUAL => 3;
use constant PAYMENT_PAYPAL => 4;

my @types =
  (
   {
    id => PAYMENT_CC,
    name => 'CC',
    desc => 'Credit Card',
    require => [ qw/cardNumber cardExpiry ccName/ ],
   },
   {
    id => PAYMENT_CHEQUE,
    name => 'Cheque',
    desc => 'Cheque',
    require => [],
   },
   {
    id => PAYMENT_CALLME,
    name => 'CallMe',
    desc => 'Call customer for payment',
    require => [],
   },
   {
    id => PAYMENT_MANUAL,
    name => 'Manual',
    desc => 'Manual',
    require => [],
   },
   {
    id => PAYMENT_PAYPAL,
    name => "PayPal",
    desc => "PayPal",
    require => [],
   },
  );

=item payment_types($cfg)

Returns payment type ids, and hashes describing each of the configured
payment types.

These are used to generate the tags used for testing whether payment
types are available.  Also used for validating payment type
information.

=cut

sub payment_types {
  my ($cfg) = @_;

  $cfg ||= BSE::Cfg->single;

  my %types = map { $_->{id} => $_ } @types;

  my @payment_types = split /,/, $cfg->entry('shop', 'payment_types', '0');

  my %all_types = map { $_ => 1 } keys %types, @payment_types;
  
  for my $type (keys %all_types) {
    my $hash = $types{$type}; # avoid autovivification
    my $name = $cfg->entry('payment type names', $type, $hash->{name} || "Type 0 has no name");
    my $desc = $cfg->entry('payment type descs', $type, 
			   $hash->{desc} || $name);
    my $enabled = !$cfg->entry('payment type disable', $hash->{name}, 0);
    my @require = $hash->{require} ? @{$hash->{require}} : ();
    @require = split /,/, $cfg->entry('payment type required', $type,
				      join ",", @require);
    $types{$type} = 
      {
       id => $type,
       name => $name, 
       desc => $desc,
       require => \@require,
       sort => scalar $cfg->entry("payment type sort", $hash->{name}, $type),
      };
  }

  for my $type (@payment_types) {
    unless ($types{$type}) {
      print STDERR "** payment type $type doesn't have a name defined\n";
      next;
    }
    $types{$type}{enabled} = 1;
  }

  # credit card payments require either encrypted emails enabled or
  # an online CC processing module
  if ($types{+PAYMENT_CC}) {
    my $noencrypt = $cfg->entryBool('shop', 'noencrypt', 0);
    my $ccprocessor = $cfg->entry('shop', 'cardprocessor');

    if ($noencrypt && !$ccprocessor) {
      $types{+PAYMENT_CC}{enabled} = 0;
      $types{+PAYMENT_CC}{message} =
	"No card processor configured and encryption disabled";
    }
  }

  # paypal requires api confguration
  if ($types{+PAYMENT_PAYPAL} && $types{+PAYMENT_PAYPAL}{enabled}) {
    require BSE::PayPal;

    unless (BSE::PayPal->configured) {
      $types{+PAYMENT_PAYPAL}{enabled} = 0;
      $types{+PAYMENT_PAYPAL}{message} = "No API configuration";
    }
  }

  return sort { $a->{sort} <=> $b->{sort} } values %types;
}

1;

=head1 NAME

BSE::Shop::PaymentTypes - defines payment type constants.

=head1 SYNOPSIS

  use BSE::Shop::PaymentTypes;

  $order->set_paymentType(PAYMENT_CC);

  use BSE::Shop::PaymentTypes 'payment_types';

  my @types = payment_types();

=cut
